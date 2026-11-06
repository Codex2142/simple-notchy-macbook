import AppKit
import Combine
import Foundation
import IslandBridge

/// Observes Apple Music and Spotify playback via public `DistributedNotificationCenter` events
/// and dispatches playback controls via `NSAppleScript` when the target player is running (PRD FR-002).
@MainActor
public final class MediaAdapter: ObservableObject {
    @Published public private(set) var nowPlaying: FfiNowPlayingTrack?

    private let core: IslandCore
    private var observers: [NSObjectProtocol] = []

    public init(core: IslandCore) throws {
        self.core = core
        self.nowPlaying = try core.currentNowPlaying()
        registerDistributedNotificationObservers()
    }

    deinit {
        let center = DistributedNotificationCenter.default()
        for obs in observers {
            center.removeObserver(obs)
        }
    }

    /// Updates Now Playing state in Rust `IslandCore`, triggering a `Peek` transition when a new track starts playing.
    @discardableResult
    public func reportNowPlaying(
        sourceApp: String,
        title: String,
        artist: String,
        album: String = "",
        durationSecs: UInt32 = 0,
        elapsedSecs: UInt32 = 0,
        isPlaying: Bool = true,
        nowMs: UInt64? = nil
    ) throws -> FfiIslandViewState {
        let track = FfiNowPlayingTrack(
            sourceApp: sourceApp,
            title: title,
            artist: artist,
            album: album,
            durationSecs: durationSecs,
            elapsedSecs: elapsedSecs,
            isPlaying: isPlaying
        )
        let ts = nowMs ?? UInt64(Date().timeIntervalSince1970 * 1000.0)
        let newState = try core.updateNowPlaying(track: track, nowMs: ts)
        self.nowPlaying = try core.currentNowPlaying()
        return newState
    }

    public func togglePlayPause() {
        guard let current = nowPlaying else { return }
        runPlayerAppleScript(app: current.sourceApp, command: "playpause")
        _ = try? reportNowPlaying(
            sourceApp: current.sourceApp,
            title: current.title,
            artist: current.artist,
            album: current.album,
            durationSecs: current.durationSecs,
            elapsedSecs: current.elapsedSecs,
            isPlaying: !current.isPlaying
        )
    }

    public func nextTrack() {
        guard let current = nowPlaying else { return }
        runPlayerAppleScript(app: current.sourceApp, command: "next track")
    }

    public func previousTrack() {
        guard let current = nowPlaying else { return }
        runPlayerAppleScript(app: current.sourceApp, command: "previous track")
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
            Task { @MainActor [weak self] in
                guard !title.isEmpty else { return }
                _ = try? self?.reportNowPlaying(
                    sourceApp: "Spotify",
                    title: title,
                    artist: artist,
                    album: album,
                    durationSecs: UInt32(max(0, duration / 1000)),
                    isPlaying: state == "Playing"
                )
            }
        }

        observers = [musicObs, spotifyObs]
    }

    private func runPlayerAppleScript(app: String, command: String) {
        guard app == "Music" || app == "Spotify" else { return }
        let bundleID = app == "Music" ? "com.apple.Music" : "com.spotify.client"
        let isRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
        guard isRunning else { return }

        let scriptSource = "tell application \"\(app)\" to \(command)"
        if let script = NSAppleScript(source: scriptSource) {
            var errorDict: NSDictionary?
            script.executeAndReturnError(&errorDict)
        }
    }
}
