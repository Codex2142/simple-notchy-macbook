import AppKit
import Foundation
import CoreGraphics
import IslandBridge
import IslandWindow
import IslandIntegrations
import IslandFeatures

@main
struct IslandSelfTest {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #fileID, line: Int = #line) {
        if !condition() {
            fputs("FAIL [\(file):\(line)]: \(message)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    static func main() async throws {
        print("==> Running Project Island macOS Swift + UniFFI Self-Tests...")

        // 1. Notched MacBook Pro 14" geometry test
        let notchedMetrics = ScreenMetrics(
            displayUUID: "UUID-MBP-14",
            displayName: "Built-in Liquid Retina XDR Display",
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaTop: 37,
            auxiliaryTopLeftWidth: 664,
            auxiliaryTopRightWidth: 664
        )
        let notchedGeo = NotchDetector.calculateGeometry(for: notchedMetrics)
        check(notchedGeo.hasHardwareNotch, "Expected hardware notch on MBP 14 metrics")
        check(notchedGeo.notchRect.width == 184, "Expected notch width 184, got \(notchedGeo.notchRect.width)")
        check(notchedGeo.notchRect.height == 37, "Expected notch height 37, got \(notchedGeo.notchRect.height)")
        check(abs(notchedGeo.notchRect.midX - 756) <= 1.0, "Expected top-centered notch midX ~756")
        check(notchedGeo.notchRect.maxY == 982, "Expected notch flush with top edge 982")

        let expandedRect = notchedGeo.frame(for: .expanded)
        check(expandedRect.width > notchedGeo.collapsedFrame.width, "Expanded width should exceed collapsed width")
        check(expandedRect.height > notchedGeo.collapsedFrame.height, "Expanded height should exceed collapsed height")

        // 2. External monitor virtual island geometry test
        let externalMetrics = ScreenMetrics(
            displayUUID: "UUID-EXT-27",
            displayName: "LG UltraFine",
            frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
            safeAreaTop: 0,
            auxiliaryTopLeftWidth: nil,
            auxiliaryTopRightWidth: nil
        )
        let extGeo = NotchDetector.calculateGeometry(for: externalMetrics)
        check(!extGeo.hasHardwareNotch, "External monitor should use virtual island")
        check(extGeo.collapsedFrame.width == 200, "Expected virtual island width 200")
        check(extGeo.collapsedFrame.height == 32, "Expected virtual island height 32")
        check(extGeo.collapsedFrame.maxY == 1440, "Expected virtual island flush with top edge 1440")

        // 3. Swift <-> Rust UniFFI roundtrip test
        let core = try IslandCore.newInMemory()
        let initial = try core.currentState()
        check(initial.mode == .collapsed, "Initial FFI state should be .collapsed")

        let expanded = try core.expand(nowMs: 1_000)
        check(expanded.mode == .expanded, "Expanded FFI state should be .expanded")

        let pinned = try core.pin(nowMs: 1_100)
        check(pinned.mode == .pinned, "Pinned FFI state should be .pinned")

        let unpinned = try core.unpin(nowMs: 1_200)
        check(unpinned.mode == .expanded, "Unpin while interacting should stay .expanded")

        let _ = try core.setInteracting(interacting: false, nowMs: 1_300)
        let collapsed = try core.tryAutoCollapse(expectedEpoch: nil, nowMs: 1_600)
        check(collapsed.mode == .collapsed, "Auto-collapse after interaction ends should return to .collapsed")

        // 4. Display profile persistence over UniFFI
        let profile = ConnectedDisplay(metrics: notchedMetrics, geometry: notchedGeo).toFfiProfile()
        try core.registerDisplayProfile(profile: profile)
        let profiles = try core.listDisplayProfiles()
        check(profiles.count == 1, "Expected 1 persisted display profile")
        check(profiles.first?.displayUuid == "UUID-MBP-14", "Expected persisted UUID-MBP-14")

        // 5. WindowLevelManager & HoverController & IslandWindowController tests
        let collapsedLevel = WindowLevelManager.windowLevel(for: .collapsed)
        let expandedLevel = WindowLevelManager.windowLevel(for: .expanded)
        check(expandedLevel > collapsedLevel, "Expanded window level should sit above collapsed level")

        let hover = HoverController(hoverInDelayMs: 20, hoverOutGraceMs: 20)
        var detectedSwipe: HoverController.SwipeDirection?
        hover.onSwipeGesture = { dir in detectedSwipe = dir }
        hover.handleScrollDelta(deltaX: 0, deltaY: 22)
        check(detectedSwipe == .down, "Expected swipe down gesture")

        let controllerCore = try IslandCore.newInMemory()
        let windowController = try IslandWindowController(core: controllerCore, hoverController: hover)
        check(windowController.viewState.mode == .collapsed, "WindowController starts in .collapsed")
        windowController.toggleExpandedOrPinned()
        try await Task.sleep(nanoseconds: 25_000_000)
        check(windowController.viewState.mode == .expanded, "toggleExpandedOrPinned transitions to .expanded")
        windowController.togglePin()
        try await Task.sleep(nanoseconds: 25_000_000)
        check(windowController.viewState.mode == .pinned, "togglePin transitions to .pinned")
        windowController.collapseNow()
        try await Task.sleep(nanoseconds: 25_000_000)
        check(windowController.viewState.mode == .collapsed, "collapseNow returns to .collapsed")

        // 6. Task 7: KeychainAdapter, PermissionManager, and SettingsStore tests
        let keychain = KeychainAdapter(service: "com.projectisland.test", inMemoryFallback: true)
        try keychain.setSecret("secret-api-token-123", for: "local_api")
        let loadedSecret = try keychain.getSecret(for: "local_api")
        check(loadedSecret == "secret-api-token-123", "Expected Keychain secret roundtrip")
        try keychain.deleteSecret(for: "local_api")
        let deletedSecret = try keychain.getSecret(for: "local_api")
        check(deletedSecret == nil, "Expected deleted Keychain secret to be nil")

        let permissions = PermissionManager(initialClipboardConsent: true)
        check(permissions.isClipboardCaptureAuthorized, "Clipboard consent initialized to true")

        let settings = try SettingsStore(core: controllerCore)
        check(settings.isModuleEnabled("clipboard"), "Default clipboard module enabled")
        try settings.setModuleEnabled("clipboard", enabled: false)
        check(!settings.isModuleEnabled("clipboard"), "Toggled clipboard module to disabled")

        let updatedRetention = FfiRetentionPolicy(
            clipboardDays: 14,
            timerHistoryDays: 120,
            activityEventsDays: 14,
            logsDays: 7
        )
        try settings.updateRetentionPolicy(updatedRetention)
        check(settings.retentionPolicy.clipboardDays == 14, "Retention policy updated to 14 days")

        // 7. Tasks 8 & 9: Clipboard Manager & Privacy Filtering tests
        let pasteboard = try PasteboardMonitor(core: controllerCore)
        let captured = try pasteboard.captureCandidate(
            text: "https://example.com/project-island",
            sourceApp: "Safari"
        )
        check(pasteboard.items.count == 1, "Expected 1 captured clipboard item")
        check(captured.textContent == "https://example.com/project-island", "Clipboard text matches")

        // Verify ConcealedType is blocked
        var concealedBlocked = false
        do {
            try pasteboard.captureCandidate(
                text: "super-secret-password",
                sourceApp: "1Password",
                pasteboardTypes: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]
            )
        } catch {
            concealedBlocked = true
        }
        check(concealedBlocked, "ConcealedType password copy must be blocked by privacy filter")
        check(pasteboard.items.count == 1, "Blocked item must not be stored")

        try pasteboard.togglePin(for: captured)
        check(pasteboard.items.first?.isPinned == true, "Clipboard item pinned")

        pasteboard.searchQuery = "project-island"
        try pasteboard.refreshItems()
        check(pasteboard.items.count == 1, "Search query matched item")

        try pasteboard.deleteItem(captured)
        check(pasteboard.items.isEmpty, "Deleted clipboard item")

        // 8. Task 10: Timer, Pomodoro & KeepAwake Live Activity tests
        let keepAwake = try KeepAwakeAdapter(core: controllerCore)
        let session = try keepAwake.startSession(
            kind: "pomodoro",
            label: "Deep Work",
            durationSecs: 1500,
            enableKeepAwake: true
        )
        check(session.kind == "pomodoro", "Started pomodoro session")
        check(keepAwake.isAwakeActive, "IOPMAssertion Keep Awake should be active")
        let activityState = try controllerCore.currentState()
        check(activityState.mode == .activity, "Starting Pomodoro transitions Island to .activity mode")
        check(activityState.activeActivity?.title == "25:00", "Activity title formatted as 25:00")

        keepAwake.stopActiveSession(status: "completed")
        check(!keepAwake.isAwakeActive, "IOPMAssertion released after stopping session")
        check(keepAwake.recentSessions.first?.status == "completed", "Session recorded as completed in SQLite")
        let postTimerState = try controllerCore.currentState()
        check(postTimerState.mode == .collapsed, "Stopping session returns Island to .collapsed")

        // 9. Task 11: Media Now Playing & Peek transition tests
        let media = try MediaAdapter(core: controllerCore)
        let peekState = try media.reportNowPlaying(
            sourceApp: "Music",
            title: "Starlight",
            artist: "Muse",
            album: "Black Holes and Revelations",
            durationSecs: 240,
            elapsedSecs: 1,
            isPlaying: true,
            nowMs: 5_000
        )
        check(peekState.mode == .peek, "New playing track transitions Island to .peek mode")
        check(peekState.activePeek?.title == "Starlight", "Peek title matches track")
        check(media.nowPlaying?.artist == "Muse", "NowPlaying artist updated")

        media.togglePlayPause()
        check(media.nowPlaying?.isPlaying == false, "togglePlayPause toggles playing flag")

        // 10. Task 12: System Telemetry & Volume/Battery HUD Peek tests
        let _ = try controllerCore.tryAutoCollapse(expectedEpoch: nil, nowMs: 5_500)
        let sysMetrics = try SystemMetricsAdapter(core: controllerCore)
        check(sysMetrics.telemetry.memoryTotalGb >= 1.0, "Host physical memory total >= 1GB")
        check(sysMetrics.telemetry.batteryPercent <= 100, "Battery percentage within 0..100")

        let volPeekState = try sysMetrics.reportVolumeChange(volumePercent: 65, isMuted: false, nowMs: 6_000)
        check(volPeekState.mode == .peek, "Volume change triggers HUD .peek mode")
        check(volPeekState.activePeek?.title == "Volume 65%", "Volume HUD Peek title matches")

        // 11. Task 13: Quick Notes & File Shelf tests
        let notesShelf = try NotesShelfStore(core: controllerCore)
        let savedNote = try notesShelf.saveNote(title: "Idea", content: "Ship Project Island M3")
        check(notesShelf.notes.count == 1, "Expected 1 saved Quick Note")
        check(savedNote.content == "Ship Project Island M3", "Note content matches")

        let fileURL = URL(fileURLWithPath: "/tmp/project-island-demo.txt")
        let shelfItem = try notesShelf.addFileToShelf(url: fileURL)
        check(notesShelf.shelfItems.count == 1, "Expected 1 item in File Shelf")
        check(shelfItem.displayName == "project-island-demo.txt", "Shelf display name matches")

        try notesShelf.removeShelfItem(shelfItem)
        check(notesShelf.shelfItems.isEmpty, "Removed item from File Shelf")
        try notesShelf.deleteNote(savedNote)
        check(notesShelf.notes.isEmpty, "Deleted Quick Note")

        print("==> PASS: All M0-M3 Swift + UniFFI + Window Engine + Feature Vertical Slices succeeded!")
    }
}
