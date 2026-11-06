import AppKit
import Combine
import Foundation
import IslandBridge

/// Integrates deeply with Spotify (and Apple Music) via `DistributedNotificationCenter` and `NSAppleScript`,
/// providing real-time playback controls, seek, artwork, and live synced `.lrc` lyrics cached in SQLite.
@MainActor
public final class MediaAdapter: ObservableObject {
    @Published public private(set) var nowPlaying: FfiNowPlayingTrack?
    @Published public private(set) var lyricsSnapshot: FfiLyricSyncSnapshot?
    @Published public private(set) var isLoadingLyrics: Bool = false
    @Published public var showLyrics: Bool = true

    private let core: IslandCore
    private let enableLivePolling: Bool
    private var observers: [NSObjectProtocol] = []
    private var pollTask: Task<Void, Never>?
    private var lyricTickTask: Task<Void, Never>?
    private var lyricsFetchTask: Task<Void, Never>?
    private var lastFetchedTrackKey: String = ""

    public init(core: IslandCore, enableLivePolling: Bool = false) throws {
        self.core = core
        self.enableLivePolling = enableLivePolling
        self.nowPlaying = try core.currentNowPlaying()
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
        lyricTickTask?.cancel()
        lyricsFetchTask?.cancel()
    }

    /// Updates Now Playing state in Rust `IslandCore`, triggering a `Peek` transition when a new track starts playing,
    /// and synchronizes `.lrc` lyrics for the current `elapsedMs`.
    @discardableResult
    public func reportNowPlaying(
        sourceApp: String,
        title: String,
        artist: String,
        album: String = "",
        artworkUrl: String = "",
        durationSecs: UInt32 = 0,
        elapsedSecs: UInt32 = 0,
        elapsedMs: UInt64? = nil,
        isPlaying: Bool = true,
        nowMs: UInt64? = nil
    ) throws -> FfiIslandViewState {
        let resolvedElapsedMs = elapsedMs ?? UInt64(elapsedSecs) * 1000
        let track = FfiNowPlayingTrack(
            sourceApp: sourceApp,
            title: title,
            artist: artist,
            album: album,
            artworkUrl: artworkUrl,
            durationSecs: durationSecs,
            elapsedSecs: elapsedSecs,
            elapsedMs: resolvedElapsedMs,
            isPlaying: isPlaying
        )
        let ts = nowMs ?? UInt64(Date().timeIntervalSince1970 * 1000.0)
        let newState = try core.updateNowPlaying(track: track, nowMs: ts)
        self.nowPlaying = try core.currentNowPlaying()

        syncOrFetchLyrics(title: title, artist: artist, elapsedMs: resolvedElapsedMs)
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

    public func togglePlayPause() {
        if let current = nowPlaying {
            runPlayerAppleScript(app: current.sourceApp, command: "playpause")
            _ = try? reportNowPlaying(
                sourceApp: current.sourceApp,
                title: current.title,
                artist: current.artist,
                album: current.album,
                artworkUrl: current.artworkUrl,
                durationSecs: current.durationSecs,
                elapsedSecs: current.elapsedSecs,
                elapsedMs: current.elapsedMs,
                isPlaying: !current.isPlaying
            )
            scheduleQuickPoll()
        } else {
            launchOrPlaySpotify()
        }
    }

    public func nextTrack() {
        let app = nowPlaying?.sourceApp ?? "Spotify"
        runPlayerAppleScript(app: app, command: "next track")
        scheduleQuickPoll()
    }

    public func previousTrack() {
        let app = nowPlaying?.sourceApp ?? "Spotify"
        runPlayerAppleScript(app: app, command: "previous track")
        scheduleQuickPoll()
    }

    public func seek(toSeconds seconds: Double) {
        guard let current = nowPlaying else { return }
        let clamped = max(0.0, min(seconds, Double(max(1, current.durationSecs))))
        let formattedSecs = String(format: "%.2f", clamped)
        runPlayerAppleScript(app: current.sourceApp, command: "set player position to \(formattedSecs)")

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
    }

    public func launchOrPlaySpotify() {
        let bundleID = "com.spotify.client"
        let isRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
        if isRunning {
            runPlayerAppleScript(app: "Spotify", command: "playpause")
            scheduleQuickPoll()
        } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    self?.runPlayerAppleScript(app: "Spotify", command: "play")
                    self?.scheduleQuickPoll()
                }
            }
        }
    }

    // MARK: - Live Spotify & Apple Music Synchronization

    private func startLivePolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.pollActivePlayers()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        lyricTickTask?.cancel()
        lyricTickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, let self else { break }
                self.advanceElapsedTick()
            }
        }
    }

    private func scheduleQuickPoll() {
        guard enableLivePolling else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            self?.pollActivePlayers()
        }
    }

    private func advanceElapsedTick() {
        guard let current = nowPlaying, current.isPlaying else { return }
        let durationMs = UInt64(current.durationSecs) * 1000
        let nextMs = durationMs > 0 ? min(durationMs, current.elapsedMs + 250) : (current.elapsedMs + 250)
        let nextSecs = UInt32(nextMs / 1000)

        _ = try? reportNowPlaying(
            sourceApp: current.sourceApp,
            title: current.title,
            artist: current.artist,
            album: current.album,
            artworkUrl: current.artworkUrl,
            durationSecs: current.durationSecs,
            elapsedSecs: nextSecs,
            elapsedMs: nextMs,
            isPlaying: true
        )
    }

    public func pollActivePlayers() {
        if isAppRunning(bundleID: "com.spotify.client"), pollSpotifyViaAppleScript() {
            return
        }
        if isAppRunning(bundleID: "com.apple.Music") {
            _ = pollMusicViaAppleScript()
        }
    }

    private func pollSpotifyViaAppleScript() -> Bool {
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
            set tPos to player position
            set tState to (player state as string)
            return tName & "|||" & tArtist & "|||" & tAlbum & "|||" & (tDur as string) & "|||" & tArt & "|||" & (tPos as string) & "|||" & tState
        end tell
        """
        guard let output = executeAppleScriptString(scriptSource), output != "STOPPED" else {
            return false
        }
        let parts = output.components(separatedBy: "|||")
        guard parts.count >= 7 else { return false }

        let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        let artist = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let rawDuration = Double(parts[3].replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let durationSecs = UInt32(max(0, rawDuration > 1000 ? Int(rawDuration / 1000.0) : Int(rawDuration)))
        let artworkUrl = parts[4].trimmingCharacters(in: .whitespacesAndNewlines)
        let posSecs = Double(parts[5].replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let stateStr = parts[6].lowercased()
        let isPlaying = stateStr.contains("playing")

        let elapsedMs = UInt64(max(0.0, posSecs * 1000.0))
        let elapsedSecs = UInt32(max(0.0, posSecs.rounded(.down)))

        _ = try? reportNowPlaying(
            sourceApp: "Spotify",
            title: title,
            artist: artist,
            album: album,
            artworkUrl: artworkUrl,
            durationSecs: durationSecs,
            elapsedSecs: elapsedSecs,
            elapsedMs: elapsedMs,
            isPlaying: isPlaying
        )
        return true
    }

    private func pollMusicViaAppleScript() -> Bool {
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
        guard let output = executeAppleScriptString(scriptSource), output != "STOPPED" else {
            return false
        }
        let parts = output.components(separatedBy: "|||")
        guard parts.count >= 6 else { return false }

        let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        let artist = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let durSecs = Double(parts[3].replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let posSecs = Double(parts[4].replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let isPlaying = parts[5].lowercased().contains("playing")

        _ = try? reportNowPlaying(
            sourceApp: "Music",
            title: title,
            artist: artist,
            album: album,
            artworkUrl: "",
            durationSecs: UInt32(max(0.0, durSecs)),
            elapsedSecs: UInt32(max(0.0, posSecs)),
            elapsedMs: UInt64(max(0.0, posSecs * 1000.0)),
            isPlaying: isPlaying
        )
        return true
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
                let currentMs = self.nowPlaying?.elapsedMs ?? elapsedMs
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
        request.setValue("ProjectIsland/0.1 (macOS Dynamic Island)", forHTTPHeaderField: "User-Agent")
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
        request.setValue("ProjectIsland/0.1 (macOS Dynamic Island)", forHTTPHeaderField: "User-Agent")
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
                self?.scheduleQuickPoll()
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
            let duration = (info?["Duration"] as? Int) ?? 0
            let positionSecs = (info?["Playback Position"] as? Double) ?? 0
            Task { @MainActor [weak self] in
                guard !title.isEmpty else { return }
                _ = try? self?.reportNowPlaying(
                    sourceApp: "Spotify",
                    title: title,
                    artist: artist,
                    album: album,
                    artworkUrl: self?.nowPlaying?.artworkUrl ?? "",
                    durationSecs: UInt32(max(0, duration > 1000 ? duration / 1000 : duration)),
                    elapsedSecs: UInt32(max(0.0, positionSecs)),
                    elapsedMs: UInt64(max(0.0, positionSecs * 1000.0)),
                    isPlaying: state == "Playing"
                )
                self?.scheduleQuickPoll()
            }
        }

        observers = [musicObs, spotifyObs]
    }

    private func isAppRunning(bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    private func executeAppleScriptString(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorDict: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorDict)
        if errorDict != nil {
            return nil
        }
        return descriptor.stringValue
    }

    private func runPlayerAppleScript(app: String, command: String) {
        guard app == "Music" || app == "Spotify" else { return }
        let bundleID = app == "Music" ? "com.apple.Music" : "com.spotify.client"
        guard isAppRunning(bundleID: bundleID) else { return }

        let scriptSource = "tell application \"\(app)\" to \(command)"
        _ = executeAppleScriptString(scriptSource)
    }
}
