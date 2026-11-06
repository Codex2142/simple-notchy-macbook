import AppKit
import Combine
import Darwin
import Foundation
import IslandBridge

/// Integrates deeply with Spotify and Apple Music via `DistributedNotificationCenter`, `NSAppleScript`,
/// `/usr/bin/osascript`, and `MediaRemote` fallback, providing low-latency playback controls,
/// artwork resolution, circular progress tracking, and 20Hz timestamp-synced `.lrc` lyrics.
@MainActor
public final class MediaAdapter: ObservableObject {
    @Published public private(set) var nowPlaying: FfiNowPlayingTrack?
    @Published public private(set) var lyricsSnapshot: FfiLyricSyncSnapshot?
    @Published public private(set) var isLoadingLyrics: Bool = false
    @Published public private(set) var playbackProgress: Double = 0.0
    @Published public private(set) var liveElapsedSecs: UInt32 = 0
    @Published public var showLyrics: Bool = true

    private let core: IslandCore
    private let enableLivePolling: Bool
    private var observers: [NSObjectProtocol] = []
    private var pollTask: Task<Void, Never>?
    private var highFreqSyncTask: Task<Void, Never>?
    private var lyricsFetchTask: Task<Void, Never>?
    private var artworkFetchTask: Task<Void, Never>?

    private var anchorElapsedMs: UInt64 = 0
    private var anchorUptimeMs: UInt64 = 0
    private var lastFetchedTrackKey: String = ""
    private var lastArtworkTrackKey: String = ""

    /// Lead compensation (ms) so synced lyrics appear right on the vocal beat rather than lagging behind IPC.
    private let lyricLeadCompensationMs: UInt64 = 120

    public init(core: IslandCore, enableLivePolling: Bool = false) throws {
        self.core = core
        self.enableLivePolling = enableLivePolling
        self.nowPlaying = try core.currentNowPlaying()
        self.anchorUptimeMs = Self.uptimeMs()
        if let current = self.nowPlaying {
            self.anchorElapsedMs = current.elapsedMs
            self.liveElapsedSecs = current.elapsedSecs
            self.playbackProgress = Self.computeProgress(elapsedMs: current.elapsedMs, durationSecs: current.durationSecs)
        }
        registerDistributedNotificationObservers()

        if enableLivePolling {
            startLivePolling()
        }
    }

    deinit {
        let center = DistributedNotificationCenter.default()
        for obs in observers {
            center.removeObserver(obs)
        }
        pollTask?.cancel()
        highFreqSyncTask?.cancel()
        lyricsFetchTask?.cancel()
        artworkFetchTask?.cancel()
    }

    /// Updates Now Playing state in Rust `IslandCore`, resets progress/artwork on track change,
    /// and synchronizes `.lrc` lyrics for the current `elapsedMs`.
    @discardableResult
    public func reportNowPlaying(
        sourceApp: String,
        title: String,
        artist: String,
        album: String = "",
        artworkUrl: String = "",
        spotifyTrackId: String = "",
        durationSecs: UInt32 = 0,
        elapsedSecs: UInt32 = 0,
        elapsedMs: UInt64? = nil,
        isPlaying: Bool = true,
        nowMs: UInt64? = nil
    ) throws -> FfiIslandViewState {
        let previous = self.nowPlaying
        let isSameTrack = previous?.title == title && previous?.artist == artist && previous?.sourceApp == sourceApp

        let resolvedArtwork: String
        if !artworkUrl.isEmpty {
            resolvedArtwork = artworkUrl
        } else if isSameTrack, let prevArt = previous?.artworkUrl, !prevArt.isEmpty {
            resolvedArtwork = prevArt
        } else {
            resolvedArtwork = ""
        }

        let resolvedElapsedMs = elapsedMs ?? (UInt64(elapsedSecs) * 1000)
        let resolvedElapsedSecs = UInt32(resolvedElapsedMs / 1000)

        let track = FfiNowPlayingTrack(
            sourceApp: sourceApp,
            title: title,
            artist: artist,
            album: album,
            artworkUrl: resolvedArtwork,
            durationSecs: durationSecs,
            elapsedSecs: resolvedElapsedSecs,
            elapsedMs: resolvedElapsedMs,
            isPlaying: isPlaying
        )

        let ts = nowMs ?? UInt64(Date().timeIntervalSince1970 * 1000.0)
        let newState = try core.updateNowPlaying(track: track, nowMs: ts)
        self.nowPlaying = try core.currentNowPlaying()

        // Update monotonic playback anchor & progress
        self.anchorElapsedMs = resolvedElapsedMs
        self.anchorUptimeMs = Self.uptimeMs()
        self.liveElapsedSecs = resolvedElapsedSecs
        self.playbackProgress = Self.computeProgress(elapsedMs: resolvedElapsedMs, durationSecs: durationSecs)

        if !isSameTrack {
            self.lyricsSnapshot = nil
        }

        syncOrFetchLyrics(title: title, artist: artist, elapsedMs: resolvedElapsedMs + (isPlaying ? lyricLeadCompensationMs : 0))

        if resolvedArtwork.isEmpty, enableLivePolling {
            fetchArtworkIfNeeded(sourceApp: sourceApp, title: title, artist: artist, spotifyTrackId: spotifyTrackId)
        }

        return newState
    }

    /// Caches and parses `.lrc` lyrics for a track via Rust `IslandCore` and updates `lyricsSnapshot`.
    @discardableResult
    public func cacheLyrics(
        title: String,
        artist: String,
        lrcContent: String,
        elapsedMs: UInt64? = nil
    ) throws -> FfiLyricSyncSnapshot {
        let targetMs = elapsedMs ?? nowPlaying?.elapsedMs ?? 0
        let snapshot = try core.cacheAndParseLyrics(
            title: title,
            artist: artist,
            lrcContent: lrcContent,
            elapsedMs: targetMs
        )
        self.lyricsSnapshot = snapshot
        return snapshot
    }

    // MARK: - Playback Controls (Spotify & Apple Music)

    public func togglePlayPause() {
        let targetApp = nowPlaying?.sourceApp ?? (isAppRunning(bundleID: "com.spotify.client") ? "Spotify" : "Music")
        if let current = nowPlaying {
            let nextPlaying = !current.isPlaying
            let currentMs = currentInterpolatedElapsedMs()
            _ = try? reportNowPlaying(
                sourceApp: current.sourceApp,
                title: current.title,
                artist: current.artist,
                album: current.album,
                artworkUrl: current.artworkUrl,
                durationSecs: current.durationSecs,
                elapsedSecs: UInt32(currentMs / 1000),
                elapsedMs: currentMs,
                isPlaying: nextPlaying
            )
            dispatchPlayerCommand(app: targetApp, appleScriptCmd: "playpause", mediaRemoteCmd: 2)
        } else {
            launchOrPlaySpotify()
        }
    }

    public func nextTrack() {
        let targetApp = nowPlaying?.sourceApp ?? "Spotify"
        // Optimistically reset progress for snappy visual feedback
        self.playbackProgress = 0.0
        self.liveElapsedSecs = 0
        self.anchorElapsedMs = 0
        self.anchorUptimeMs = Self.uptimeMs()

        dispatchPlayerCommand(app: targetApp, appleScriptCmd: "next track", mediaRemoteCmd: 4)
    }

    public func previousTrack() {
        let targetApp = nowPlaying?.sourceApp ?? "Spotify"
        self.playbackProgress = 0.0
        self.liveElapsedSecs = 0
        self.anchorElapsedMs = 0
        self.anchorUptimeMs = Self.uptimeMs()

        // In Spotify, if playback is past 3s, a single `previous track` only rewinds to 0:00.
        // Setting player position to 0 first guarantees skipping to the actual previous song.
        let scriptCmd: String
        if targetApp == "Spotify" {
            scriptCmd = "set player position to 0\nprevious track"
        } else {
            scriptCmd = "previous track"
        }
        dispatchPlayerCommand(app: targetApp, appleScriptCmd: scriptCmd, mediaRemoteCmd: 5)
    }

    public func seek(toSeconds seconds: Double) {
        guard let current = nowPlaying else { return }
        let clamped = max(0.0, min(seconds, Double(max(1, current.durationSecs))))
        let formattedSecs = String(format: "%.2f", clamped)

        let newElapsedSecs = UInt32(clamped.rounded(.down))
        let newElapsedMs = UInt64(clamped * 1000.0)
        _ = try? reportNowPlaying(
            sourceApp: current.sourceApp,
            title: current.title,
            artist: current.artist,
            album: current.album,
            artworkUrl: current.artworkUrl,
            durationSecs: current.durationSecs,
            elapsedSecs: newElapsedSecs,
            elapsedMs: newElapsedMs,
            isPlaying: current.isPlaying
        )

        dispatchPlayerCommand(
            app: current.sourceApp,
            appleScriptCmd: "set player position to \(formattedSecs)",
            mediaRemoteCmd: nil
        )
    }

    public func launchOrPlaySpotify() {
        let bundleID = "com.spotify.client"
        if isAppRunning(bundleID: bundleID) {
            dispatchPlayerCommand(app: "Spotify", appleScriptCmd: "playpause", mediaRemoteCmd: 2)
        } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    self?.dispatchPlayerCommand(app: "Spotify", appleScriptCmd: "play", mediaRemoteCmd: 0)
                }
            }
        }
    }

    // MARK: - Live Polling & 20Hz Timestamp Synchronizer

    private func startLivePolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.pollActivePlayersAsync()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }

        // 50ms (20Hz) high-precision local timestamp synchronizer for lyrics and smooth circular progress ring
        highFreqSyncTask?.cancel()
        highFreqSyncTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled, let self else { break }
                self.tickHighPrecisionSync()
            }
        }
    }

    private func scheduleImmediateStateRefresh() {
        guard enableLivePolling else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            await self?.pollActivePlayersAsync()
            try? await Task.sleep(nanoseconds: 350_000_000)
            await self?.pollActivePlayersAsync()
        }
    }

    private func currentInterpolatedElapsedMs() -> UInt64 {
        guard let current = nowPlaying else { return 0 }
        guard current.isPlaying else { return anchorElapsedMs }
        let nowUp = Self.uptimeMs()
        let delta = nowUp >= anchorUptimeMs ? (nowUp - anchorUptimeMs) : 0
        let durationMs = UInt64(current.durationSecs) * 1000
        let raw = anchorElapsedMs + delta
        return durationMs > 0 ? min(durationMs, raw) : raw
    }

    private func tickHighPrecisionSync() {
        guard let current = nowPlaying, current.isPlaying else { return }
        let liveMs = currentInterpolatedElapsedMs()
        let liveSecs = UInt32(liveMs / 1000)
        if liveSecs != liveElapsedSecs {
            liveElapsedSecs = liveSecs
        }
        let nextProgress = Self.computeProgress(elapsedMs: liveMs, durationSecs: current.durationSecs)
        if abs(nextProgress - playbackProgress) >= 0.0015 {
            playbackProgress = nextProgress
        }

        // Evaluate cached lyrics at `liveMs + lyricLeadCompensationMs`
        let targetLyricMs = liveMs + lyricLeadCompensationMs
        if let updatedSnap = try? core.getCachedLyricsSnapshot(
            title: current.title,
            artist: current.artist,
            elapsedMs: targetLyricMs
        ) {
            if lyricsSnapshot?.currentIndex != updatedSnap.currentIndex
                || lyricsSnapshot?.currentLine != updatedSnap.currentLine
            {
                lyricsSnapshot = updatedSnap
            }
        }
    }

    public func pollActivePlayersAsync() async {
        let spotifyRunning = isAppRunning(bundleID: "com.spotify.client")
        let musicRunning = isAppRunning(bundleID: "com.apple.Music")

        if spotifyRunning {
            if let state = await Task.detached(priority: .userInitiated, operation: {
                Self.querySpotifyStateBlocking()
            }).value {
                _ = try? reportNowPlaying(
                    sourceApp: "Spotify",
                    title: state.title,
                    artist: state.artist,
                    album: state.album,
                    artworkUrl: state.artworkUrl,
                    spotifyTrackId: state.trackId,
                    durationSecs: state.durationSecs,
                    elapsedSecs: UInt32(state.elapsedMs / 1000),
                    elapsedMs: state.elapsedMs,
                    isPlaying: state.isPlaying
                )
                return
            }
        }

        if musicRunning {
            if let state = await Task.detached(priority: .userInitiated, operation: {
                Self.queryMusicStateBlocking()
            }).value {
                _ = try? reportNowPlaying(
                    sourceApp: "Music",
                    title: state.title,
                    artist: state.artist,
                    album: state.album,
                    artworkUrl: "",
                    durationSecs: state.durationSecs,
                    elapsedSecs: UInt32(state.elapsedMs / 1000),
                    elapsedMs: state.elapsedMs,
                    isPlaying: state.isPlaying
                )
            }
        }
    }

    private struct PolledTrackState: Sendable {
        let title: String
        let artist: String
        let album: String
        let artworkUrl: String
        let trackId: String
        let durationSecs: UInt32
        let elapsedMs: UInt64
        let isPlaying: Bool
    }

    nonisolated private static func querySpotifyStateBlocking() -> PolledTrackState? {
        let scriptSource = """
        tell application "Spotify"
            if player state is stopped then
                return "STOPPED"
            end if
            set tName to name of current track
            set tArtist to artist of current track
            set tAlbum to album of current track
            set tDur to duration of current track
            set tArt to artwork url of current track
            set tId to id of current track
            set tPos to player position
            set tState to (player state as string)
            return tName & "|||" & tArtist & "|||" & tAlbum & "|||" & (tDur as string) & "|||" & tArt & "|||" & tId & "|||" & (tPos as string) & "|||" & tState
        end tell
        """
        guard let output = runAppleScriptOrOsascriptBlocking(scriptSource), output != "STOPPED" else {
            return nil
        }
        let parts = output.components(separatedBy: "|||")
        guard parts.count >= 8 else { return nil }

        let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let artist = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let rawDuration = Double(parts[3].replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let durationSecs = UInt32(max(0, rawDuration > 1000 ? Int(rawDuration / 1000.0) : Int(rawDuration)))
        let artworkUrl = parts[4].trimmingCharacters(in: .whitespacesAndNewlines)
        let trackId = parts[5].trimmingCharacters(in: .whitespacesAndNewlines)
        let posSecs = Double(parts[6].replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let stateStr = parts[7].lowercased()
        let isPlaying = stateStr.contains("playing")

        let elapsedMs = UInt64(max(0.0, posSecs * 1000.0))
        return PolledTrackState(
            title: title,
            artist: artist,
            album: album,
            artworkUrl: artworkUrl,
            trackId: trackId,
            durationSecs: durationSecs,
            elapsedMs: elapsedMs,
            isPlaying: isPlaying
        )
    }

    nonisolated private static func queryMusicStateBlocking() -> PolledTrackState? {
        let scriptSource = """
        tell application "Music"
            if player state is stopped then
                return "STOPPED"
            end if
            set tName to name of current track
            set tArtist to artist of current track
            set tAlbum to album of current track
            set tDur to duration of current track
            set tPos to player position
            set tState to (player state as string)
            return tName & "|||" & tArtist & "|||" & tAlbum & "|||" & (tDur as string) & "|||" & (tPos as string) & "|||" & tState
        end tell
        """
        guard let output = runAppleScriptOrOsascriptBlocking(scriptSource), output != "STOPPED" else {
            return nil
        }
        let parts = output.components(separatedBy: "|||")
        guard parts.count >= 6 else { return nil }

        let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let artist = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let durSecs = Double(parts[3].replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let posSecs = Double(parts[4].replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let isPlaying = parts[5].lowercased().contains("playing")

        return PolledTrackState(
            title: title,
            artist: artist,
            album: album,
            artworkUrl: "",
            trackId: "",
            durationSecs: UInt32(max(0.0, durSecs)),
            elapsedMs: UInt64(max(0.0, posSecs * 1000.0)),
            isPlaying: isPlaying
        )
    }

    // MARK: - Multi-Path Command Execution (NSAppleScript + osascript + MediaRemote)

    private func dispatchPlayerCommand(app: String, appleScriptCmd: String, mediaRemoteCmd: UInt32?) {
        guard enableLivePolling else { return }
        guard app == "Spotify" || app == "Music" else { return }
        let bundleID = app == "Music" ? "com.apple.Music" : "com.spotify.client"
        guard isAppRunning(bundleID: bundleID) else { return }

        let fullScript = """
        tell application "\(app)"
            \(appleScriptCmd)
        end tell
        """
        Task.detached(priority: .userInitiated) {
            let ok = Self.executeCommandBlocking(fullScript)
            if !ok, let mrCmd = mediaRemoteCmd {
                Self.sendMediaRemoteCommand(mrCmd)
            }
        }
        scheduleImmediateStateRefresh()
    }

    nonisolated private static func executeCommandBlocking(_ scriptSource: String) -> Bool {
        if let script = NSAppleScript(source: scriptSource) {
            var errorDict: NSDictionary?
            script.executeAndReturnError(&errorDict)
            if errorDict == nil {
                return true
            }
        }
        return runOsascriptProcess(scriptSource) != nil
    }

    nonisolated private static func runAppleScriptOrOsascriptBlocking(_ scriptSource: String) -> String? {
        if let script = NSAppleScript(source: scriptSource) {
            var errorDict: NSDictionary?
            let descriptor = script.executeAndReturnError(&errorDict)
            if errorDict == nil, let str = descriptor.stringValue {
                return str
            }
        }
        return runOsascriptProcess(scriptSource)
    }

    nonisolated private static func runOsascriptProcess(_ scriptSource: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", scriptSource]
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    nonisolated private static func sendMediaRemoteCommand(_ command: UInt32) {
        typealias MRMediaRemoteSendCommandFn = @convention(c) (UInt32, AnyObject?) -> Bool
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY),
              let sym = dlsym(handle, "MRMediaRemoteSendCommand")
        else {
            return
        }
        let sendCmd = unsafeBitCast(sym, to: MRMediaRemoteSendCommandFn.self)
        _ = sendCmd(command, nil)
    }

    // MARK: - Spotify Artwork Resolution (oEmbed + AppleScript)

    private func fetchArtworkIfNeeded(sourceApp: String, title: String, artist: String, spotifyTrackId: String) {
        guard sourceApp == "Spotify" else { return }
        let key = "\(title.lowercased())::\(artist.lowercased())"
        guard key != lastArtworkTrackKey else { return }
        lastArtworkTrackKey = key

        artworkFetchTask?.cancel()
        artworkFetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let artUrl = await Self.resolveSpotifyArtwork(trackId: spotifyTrackId) {
                guard let current = self.nowPlaying,
                      current.title == title,
                      current.artist == artist
                else { return }
                let liveMs = self.currentInterpolatedElapsedMs()
                _ = try? self.reportNowPlaying(
                    sourceApp: current.sourceApp,
                    title: current.title,
                    artist: current.artist,
                    album: current.album,
                    artworkUrl: artUrl,
                    durationSecs: current.durationSecs,
                    elapsedSecs: UInt32(liveMs / 1000),
                    elapsedMs: liveMs,
                    isPlaying: current.isPlaying
                )
            }
        }
    }

    private static func resolveSpotifyArtwork(trackId: String) async -> String? {
        // 1. Try Spotify public oEmbed endpoint using Track ID (works even without AppleScript permission)
        let cleanId = trackId
            .replacingOccurrences(of: "spotify:track:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanId.isEmpty,
           let oembedUrl = URL(string: "https://open.spotify.com/oembed?url=https://open.spotify.com/track/\(cleanId)")
        {
            var req = URLRequest(url: oembedUrl)
            req.timeoutInterval = 5
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse,
               http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let thumb = json["thumbnail_url"] as? String,
               !thumb.isEmpty
            {
                return thumb
            }
        }

        // 2. Fallback to AppleScript / osascript `artwork url of current track`
        return await Task.detached(priority: .utility) {
            runAppleScriptOrOsascriptBlocking("tell application \"Spotify\" to return artwork url of current track")
        }.value
    }

    // MARK: - Live Synced Lyrics Lookup & SQLite Cache

    private func syncOrFetchLyrics(title: String, artist: String, elapsedMs: UInt64) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            self.lyricsSnapshot = nil
            return
        }

        if let cached = try? core.getCachedLyricsSnapshot(
            title: trimmedTitle,
            artist: trimmedArtist,
            elapsedMs: elapsedMs
        ) {
            self.lyricsSnapshot = cached
            return
        }

        let trackKey = "\(trimmedTitle.lowercased())::\(trimmedArtist.lowercased())"
        guard enableLivePolling, trackKey != lastFetchedTrackKey else { return }
        lastFetchedTrackKey = trackKey
        self.lyricsSnapshot = nil
        self.isLoadingLyrics = true

        lyricsFetchTask?.cancel()
        lyricsFetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isLoadingLyrics = false }
            if let lrc = await Self.fetchLrcFromLrclib(title: trimmedTitle, artist: trimmedArtist) {
                let currentMs = self.currentInterpolatedElapsedMs() + self.lyricLeadCompensationMs
                if let snap = try? self.core.cacheAndParseLyrics(
                    title: trimmedTitle,
                    artist: trimmedArtist,
                    lrcContent: lrc,
                    elapsedMs: currentMs
                ) {
                    self.lyricsSnapshot = snap
                }
            }
        }
    }

    private static func fetchLrcFromLrclib(title: String, artist: String) async -> String? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if let url = components?.url, let lrc = await requestLrclibSingle(url: url) {
            return lrc
        }

        var searchComponents = URLComponents(string: "https://lrclib.net/api/search")
        searchComponents?.queryItems = [
            URLQueryItem(name: "q", value: "\(title) \(artist)"),
        ]
        if let searchUrl = searchComponents?.url {
            return await requestLrclibSearch(url: searchUrl)
        }
        return nil
    }

    private static func requestLrclibSingle(url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue("ProjectIsland/0.2 (macOS Dynamic Island)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        if let synced = json["syncedLyrics"] as? String, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return synced
        }
        if let plain = json["plainLyrics"] as? String, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return plain
        }
        return nil
    }

    private static func requestLrclibSearch(url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue("ProjectIsland/0.2 (macOS Dynamic Island)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return nil
        }
        for item in items {
            if let synced = item["syncedLyrics"] as? String, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return synced
            }
        }
        for item in items {
            if let plain = item["plainLyrics"] as? String, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return plain
            }
        }
        return nil
    }

    private func registerDistributedNotificationObservers() {
        let center = DistributedNotificationCenter.default()

        let musicObs = center.addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let info = note.userInfo
            let title = (info?["Name"] as? String) ?? ""
            let artist = (info?["Artist"] as? String) ?? ""
            let album = (info?["Album"] as? String) ?? ""
            let state = (info?["Player State"] as? String) ?? ""
            let totalMs = (info?["Total Time"] as? Int) ?? 0
            Task { @MainActor [weak self] in
                guard !title.isEmpty else { return }
                _ = try? self?.reportNowPlaying(
                    sourceApp: "Music",
                    title: title,
                    artist: artist,
                    album: album,
                    durationSecs: UInt32(max(0, totalMs / 1000)),
                    isPlaying: state == "Playing"
                )
                self?.scheduleImmediateStateRefresh()
            }
        }

        let spotifyObs = center.addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let info = note.userInfo
            let title = (info?["Name"] as? String) ?? ""
            let artist = (info?["Artist"] as? String) ?? ""
            let album = (info?["Album"] as? String) ?? ""
            let state = (info?["Player State"] as? String) ?? ""
            let trackId = (info?["Track ID"] as? String) ?? ""
            let durationRaw = (info?["Duration"] as? Double) ?? Double((info?["Duration"] as? Int) ?? 0)
            let positionSecs = (info?["Playback Position"] as? Double) ?? 0
            Task { @MainActor [weak self] in
                guard !title.isEmpty else { return }
                let durationSecs = UInt32(max(0, durationRaw > 1000 ? Int(durationRaw / 1000.0) : Int(durationRaw)))
                _ = try? self?.reportNowPlaying(
                    sourceApp: "Spotify",
                    title: title,
                    artist: artist,
                    album: album,
                    artworkUrl: "",
                    spotifyTrackId: trackId,
                    durationSecs: durationSecs,
                    elapsedSecs: UInt32(max(0.0, positionSecs)),
                    elapsedMs: UInt64(max(0.0, positionSecs * 1000.0)),
                    isPlaying: state == "Playing"
                )
                self?.scheduleImmediateStateRefresh()
            }
        }

        observers = [musicObs, spotifyObs]
    }

    private func isAppRunning(bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    private static func uptimeMs() -> UInt64 {
        UInt64(ProcessInfo.processInfo.systemUptime * 1000.0)
    }

    public static func computeProgress(elapsedMs: UInt64, durationSecs: UInt32) -> Double {
        let totalMs = Double(durationSecs) * 1000.0
        guard totalMs > 0 else { return 0.0 }
        return max(0.0, min(1.0, Double(elapsedMs) / totalMs))
    }
}
