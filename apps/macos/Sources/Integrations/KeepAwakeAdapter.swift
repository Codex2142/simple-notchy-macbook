import Combine
import Foundation
import IOKit.pwr_mgt
import IslandBridge
import UserNotifications

public enum TimerState: String, Sendable, Equatable {
    case idle
    case running
    case paused
    case completed
}

/// Manages high-precision monotonic timers, macOS `IOPMAssertion` Keep Awake, and native notifications.
@MainActor
public final class KeepAwakeAdapter: ObservableObject {
    @Published public private(set) var isAwakeActive: Bool = false
    @Published public private(set) var activeSession: FfiTimerSession?
    @Published public private(set) var recentSessions: [FfiTimerSession] = []

    @Published public private(set) var timerState: TimerState = .idle
    @Published public private(set) var totalDurationSecs: UInt32 = 0
    @Published public private(set) var remainingSeconds: UInt32 = 0
    @Published public private(set) var timerProgress: Double = 0.0

    @Published public var customHours: Int = 0
    @Published public var customMinutes: Int = 5
    @Published public var customSeconds: Int = 0

    private let core: IslandCore
    private var assertionID: IOPMAssertionID = 0
    private var tickTask: Task<Void, Never>?

    private var accumulatedElapsedSecs: Double = 0.0
    private var runningAnchorUptime: Double = 0.0
    private var hasNotifiedCompletion: Bool = false
    private var currentSessionLabel: String = "Timer"

    public init(core: IslandCore) throws {
        self.core = core
        self.recentSessions = try core.listTimerSessions(limit: 20)
        requestNotificationAuthorization()
    }

    deinit {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
        }
        tickTask?.cancel()
    }

    // MARK: - Notification Permissions

    private func requestNotificationAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Timer Controls

    /// Starts a custom timer using (hours, minutes, seconds). Validates input and rejects zero/invalid duration.
    @discardableResult
    public func startCustomTimer(hours: Int, minutes: Int, seconds: Int, enableKeepAwake: Bool = false) -> Bool {
        guard hours >= 0, minutes >= 0, seconds >= 0 else { return false }
        let total = UInt32(hours * 3600 + minutes * 60 + seconds)
        guard total > 0 else { return false }

        let label = formatHhMmSs(total)
        do {
            try startSession(
                kind: "countdown",
                label: "Timer \(label)",
                durationSecs: total,
                enableKeepAwake: enableKeepAwake
            )
            return true
        } catch {
            return false
        }
    }

    /// Starts a Timer, Pomodoro, or Keep Awake session and transitions the Island to `Activity` mode.
    @discardableResult
    public func startSession(
        kind: String,
        label: String,
        durationSecs: UInt32,
        enableKeepAwake: Bool = false,
        nowSecs: Int64? = nil
    ) throws -> FfiTimerSession {
        guard durationSecs > 0 else {
            throw FfiError.Validation(message: "Timer duration must be greater than 0")
        }
        stopActiveSession(status: "cancelled")

        let ts = nowSecs ?? Int64(Date().timeIntervalSince1970)
        let session = try core.startTimerSession(
            kind: kind,
            label: label,
            durationSecs: durationSecs,
            nowSecs: ts
        )
        self.activeSession = session
        self.totalDurationSecs = durationSecs
        self.remainingSeconds = durationSecs
        self.timerProgress = 0.0
        self.accumulatedElapsedSecs = 0.0
        self.runningAnchorUptime = ProcessInfo.processInfo.systemUptime
        self.timerState = .running
        self.hasNotifiedCompletion = false
        self.currentSessionLabel = label
        self.recentSessions = (try? core.listTimerSessions(limit: 20)) ?? []

        if enableKeepAwake || kind == "keep_awake" {
            acquirePowerAssertion(reason: "Project Island: \(label)")
        }

        startMonotonicTickLoop()
        return session
    }

    public func pauseTimer() {
        guard timerState == .running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        accumulatedElapsedSecs += max(0.0, now - runningAnchorUptime)
        timerState = .paused
        tickTask?.cancel()
        tickTask = nil

        updateActivityPill(isPaused: true)
    }

    public func resumeTimer() {
        guard timerState == .paused, remainingSeconds > 0 else { return }
        runningAnchorUptime = ProcessInfo.processInfo.systemUptime
        timerState = .running
        startMonotonicTickLoop()
    }

    public func resetTimer() {
        tickTask?.cancel()
        tickTask = nil
        releasePowerAssertion()

        if let current = activeSession {
            let ts = Int64(Date().timeIntervalSince1970)
            _ = try? core.finishTimerSession(sessionId: current.id, status: "reset", nowSecs: ts)
        }

        _ = try? core.clearActivity(nowMs: UInt64(Date().timeIntervalSince1970 * 1000.0))

        self.activeSession = nil
        self.timerState = .idle
        self.totalDurationSecs = 0
        self.remainingSeconds = 0
        self.timerProgress = 0.0
        self.accumulatedElapsedSecs = 0.0
        self.hasNotifiedCompletion = false
        self.recentSessions = (try? core.listTimerSessions(limit: 20)) ?? []
    }

    public func stopActiveSession(status: String = "completed", nowSecs: Int64? = nil) {
        tickTask?.cancel()
        tickTask = nil
        releasePowerAssertion()

        guard let current = activeSession else {
            timerState = .idle
            timerProgress = 0.0
            remainingSeconds = 0
            return
        }

        let ts = nowSecs ?? Int64(Date().timeIntervalSince1970)
        _ = try? core.finishTimerSession(sessionId: current.id, status: status, nowSecs: ts)
        self.activeSession = nil
        self.timerState = status == "completed" ? .completed : .idle
        if status == "completed" {
            self.remainingSeconds = 0
            self.timerProgress = 1.0
        } else {
            self.remainingSeconds = 0
            self.timerProgress = 0.0
        }
        self.recentSessions = (try? core.listTimerSessions(limit: 20)) ?? []
    }

    // MARK: - Monotonic Precision Tick Loop

    private func startMonotonicTickLoop() {
        tickTask?.cancel()
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms tick for fluid progress
                guard !Task.isCancelled, let self else { break }
                self.evaluateMonotonicTick()
            }
        }
    }

    private func evaluateMonotonicTick() {
        guard timerState == .running, totalDurationSecs > 0 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let currentElapsed = accumulatedElapsedSecs + max(0.0, now - runningAnchorUptime)
        let total = Double(totalDurationSecs)

        if currentElapsed >= total {
            // Completed!
            self.remainingSeconds = 0
            self.timerProgress = 1.0
            self.timerState = .completed
            self.tickTask?.cancel()
            self.tickTask = nil
            self.releasePowerAssertion()

            if !hasNotifiedCompletion {
                hasNotifiedCompletion = true
                sendCompletionNotification()
            }

            if let active = activeSession {
                let ts = Int64(Date().timeIntervalSince1970)
                _ = try? core.finishTimerSession(sessionId: active.id, status: "completed", nowSecs: ts)
                self.recentSessions = (try? core.listTimerSessions(limit: 20)) ?? []
            }

            _ = try? core.startActivity(
                activity: FfiActivityInfo(
                    id: "timer-done",
                    kind: "completed",
                    title: "00:00",
                    subtitle: "Finished!"
                ),
                nowMs: UInt64(Date().timeIntervalSince1970 * 1000.0)
            )
        } else {
            let rem = UInt32(max(0.0, ceil(total - currentElapsed)))
            self.remainingSeconds = rem
            self.timerProgress = max(0.0, min(1.0, currentElapsed / total))
            updateActivityPill(isPaused: false)
        }
    }

    private func updateActivityPill(isPaused: Bool) {
        guard let active = activeSession else { return }
        let formatted = formatHhMmSs(remainingSeconds)
        let sub = isPaused ? "\(currentSessionLabel) (Paused)" : currentSessionLabel
        _ = try? core.startActivity(
            activity: FfiActivityInfo(
                id: "timer-\(active.id)",
                kind: active.kind,
                title: formatted,
                subtitle: sub
            ),
            nowMs: UInt64(Date().timeIntervalSince1970 * 1000.0)
        )
    }

    private func sendCompletionNotification() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Timer Complete"
        content.body = "\(currentSessionLabel) has finished."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "project-island-timer-\(UUID().uuidString)",
            content: content,
            trigger: nil // deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: - Power Assertion

    @discardableResult
    public func acquirePowerAssertion(reason: String) -> Bool {
        releasePowerAssertion()
        let assertionType = kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
        let assertionName = reason as CFString
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            assertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            assertionName,
            &id
        )
        if result == kIOReturnSuccess {
            self.assertionID = id
            self.isAwakeActive = true
            return true
        }
        return false
    }

    public func releasePowerAssertion() {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
        isAwakeActive = false
    }

    public func formatHhMmSs(_ totalSecs: UInt32) -> String {
        let hrs = totalSecs / 3600
        let mins = (totalSecs % 3600) / 60
        let secs = totalSecs % 60
        if hrs > 0 {
            return String(format: "%02d:%02d:%02d", hrs, mins, secs)
        } else {
            return String(format: "%02d:%02d", mins, secs)
        }
    }
}
