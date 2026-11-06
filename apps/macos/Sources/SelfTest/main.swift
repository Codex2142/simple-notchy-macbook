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

        // 2b. MacBook Air M2 notch-safe layout
        check(notchedGeo.notchSafeTopInset == 37, "Notched display must expose notchSafeTopInset == notch height")
        check(extGeo.notchSafeTopInset == 0, "External display must have zero notch inset")
        check(
            notchedGeo.expandedFrame.height >= notchedGeo.notchSafeTopInset + 280,
            "Expanded panel must leave >=280pt of content below the physical notch"
        )
        check(
            notchedGeo.wingWidth(for: .collapsed) >= 48,
            "Collapsed wings must be wide enough for artwork ring beside the physical notch"
        )
        check(
            notchedGeo.collapsedFrame.width >= notchedGeo.notchRect.width + 2 * 48,
            "Collapsed pill must extend beyond the notch cutout on both sides"
        )

        // 2c. Playback progress math for circular ring
        check(MediaAdapter.computeProgress(elapsedMs: 60_000, durationSecs: 240) == 0.25, "Progress 60s/240s == 0.25")
        check(MediaAdapter.computeProgress(elapsedMs: 999_999, durationSecs: 100) == 1.0, "Progress clamps to 1.0")
        check(MediaAdapter.computeProgress(elapsedMs: 5_000, durationSecs: 0) == 0.0, "Zero duration yields 0 progress")

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

        let testPanel = IslandPanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 40))
        check(testPanel.collectionBehavior.contains(.moveToActiveSpace), "Panel must have .moveToActiveSpace for active desktop only")
        check(!testPanel.collectionBehavior.contains(.canJoinAllSpaces), "Panel must NOT have .canJoinAllSpaces to prevent sliding during Spaces swipe")

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

        let copySuccess = pasteboard.copyToPasteboard(captured)
        check(copySuccess, "copyToPasteboard should succeed")
        check(pasteboard.copiedItemId == captured.id, "copiedItemId should match copied item")

        let secondItem = try pasteboard.captureCandidate(
            text: "Second snippet",
            sourceApp: "Notes"
        )
        pasteboard.copyToPasteboard(secondItem)
        check(pasteboard.copiedItemId == secondItem.id, "Copying another item updates active feedback to the new item")
        try pasteboard.deleteItem(secondItem)

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

        // Custom timer input validation tests
        let zeroRejected = keepAwake.startCustomTimer(hours: 0, minutes: 0, seconds: 0)
        check(!zeroRejected, "Zero duration timer must be rejected")
        let negativeRejected = keepAwake.startCustomTimer(hours: -1, minutes: 0, seconds: 0)
        check(!negativeRejected, "Negative duration timer must be rejected")

        // Monotonic timer controls: Start, Pause, Resume, Reset
        let validStarted = keepAwake.startCustomTimer(hours: 0, minutes: 1, seconds: 30)
        check(validStarted, "Valid 90s timer must be accepted")
        check(keepAwake.timerState == .running, "Timer state should be .running")
        check(keepAwake.totalDurationSecs == 90, "Total duration should be 90s")
        check(keepAwake.remainingSeconds <= 90, "Remaining seconds <= 90")

        keepAwake.pauseTimer()
        check(keepAwake.timerState == .paused, "Timer state should be .paused")
        let pausedRemaining = keepAwake.remainingSeconds

        try await Task.sleep(nanoseconds: 100_000_000)
        check(keepAwake.remainingSeconds == pausedRemaining, "Pausing timer must freeze remaining seconds")

        keepAwake.resumeTimer()
        check(keepAwake.timerState == .running, "Resumed timer should be .running")

        keepAwake.resetTimer()
        check(keepAwake.timerState == .idle, "Reset timer should return to .idle")
        check(keepAwake.timerProgress == 0.0, "Reset timer progress must return to 0.0")
        check(keepAwake.remainingSeconds == 0, "Reset timer remainingSeconds must be 0")

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

        // Verify LRC live synced lyrics caching & seek synchronization
        let sampleLrc = """
        [00:02.00] Far away
        [00:08.50] This ship is taking me far away
        [00:15.00] Far away from the memories
        """
        let initialLyrics = try media.cacheLyrics(
            title: "Starlight",
            artist: "Muse",
            lrcContent: sampleLrc,
            elapsedMs: 3_000
        )
        check(initialLyrics.hasSyncedLyrics, "Expected parsed synced lyrics")
        check(initialLyrics.currentLine == "Far away", "Expected line at 3s to be 'Far away', got '\(initialLyrics.currentLine)'")
        check(initialLyrics.nextLine == "This ship is taking me far away", "Expected next line at 3s")

        media.seek(toSeconds: 10.0)
        check(media.nowPlaying?.elapsedSecs == 10, "Expected seek to update elapsedSecs to 10")
        check(media.lyricsSnapshot?.currentLine == "This ship is taking me far away", "Expected live lyric at 10s to advance to second line")

        // Verify hover hysteresis prevents expand/collapse oscillation
        let hysteresisHover = HoverController(hoverInDelayMs: 10, hoverOutGraceMs: 10)
        let notchCenterPoint = CGPoint(x: notchedGeo.collapsedFrame.midX, y: notchedGeo.collapsedFrame.midY)
        hysteresisHover.evaluateCursorLocation(
            screenPoint: notchCenterPoint,
            geometry: notchedGeo,
            mode: .collapsed
        )
        check(hysteresisHover.isPointerInside, "Cursor inside collapsed notch should mark pointer inside")
        // Move cursor lower down inside expanded panel (outside collapsedFrame, inside expandedFrame)
        let lowerExpandedPoint = CGPoint(x: notchedGeo.expandedFrame.midX, y: notchedGeo.expandedFrame.minY + 40)
        hysteresisHover.evaluateCursorLocation(
            screenPoint: lowerExpandedPoint,
            geometry: notchedGeo,
            mode: .expanded
        )
        check(hysteresisHover.isPointerInside, "Cursor inside expanded panel must remain inside and never oscillate")

        // 10. Task 12: System Telemetry & Volume/Battery HUD Peek tests
        let _ = try controllerCore.tryAutoCollapse(expectedEpoch: nil, nowMs: 5_500)
        let sysMetrics = try SystemMetricsAdapter(core: controllerCore)
        check(sysMetrics.telemetry.memoryTotalGb >= 1.0, "Host physical memory total >= 1GB")
        check(sysMetrics.telemetry.batteryPercent <= 100, "Battery percentage within 0..100")
        _ = try sysMetrics.sampleHostMetrics()
        check(sysMetrics.telemetry.cpuUsagePercent >= 0 && sysMetrics.telemetry.cpuUsagePercent <= 100, "CPU within 0..100")
        check(sysMetrics.diskTotalGb > 0 && sysMetrics.diskUsedGb <= sysMetrics.diskTotalGb, "Disk metrics sane")

        // Auto-refresh every 2s without manual interaction
        sysMetrics.startMonitoring(intervalSeconds: 0.5)
        try await Task.sleep(nanoseconds: 1_200_000_000)
        sysMetrics.stopMonitoring()

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
