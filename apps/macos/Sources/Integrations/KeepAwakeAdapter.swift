import Combine
import Foundation
import IOKit.pwr_mgt
import IslandBridge

/// Manages macOS `IOPMAssertion` for timed Keep Awake and Pomodoro focus sessions (PRD FR-004).
@MainActor
public final class KeepAwakeAdapter: ObservableObject {
    @Published public private(set) var isAwakeActive: Bool = false
    @Published public private(set) var activeSession: FfiTimerSession?
    @Published public private(set) var recentSessions: [FfiTimerSession] = []
    @Published public private(set) var remainingSeconds: UInt32 = 0

    private let core: IslandCore
    private var assertionID: IOPMAssertionID = 0
    private var countdownTimer: Timer?

    public init(core: IslandCore) throws {
        self.core = core
        self.recentSessions = try core.listTimerSessions(limit: 20)
    }

    deinit {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
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
        stopActiveSession(status: "cancelled")

        let ts = nowSecs ?? Int64(Date().timeIntervalSince1970)
        let session = try core.startTimerSession(
            kind: kind,
            label: label,
            durationSecs: durationSecs,
            nowSecs: ts
        )
        self.activeSession = session
        self.remainingSeconds = durationSecs
        self.recentSessions = try core.listTimerSessions(limit: 20)

        if enableKeepAwake || kind == "keep_awake" {
            acquirePowerAssertion(reason: "Project Island: \(label)")
        }

        startCountdownLoop()
        return session
    }

    public func stopActiveSession(status: String = "completed", nowSecs: Int64? = nil) {
        countdownTimer?.invalidate()
        countdownTimer = nil
        releasePowerAssertion()

        guard let current = activeSession else { return }
        let ts = nowSecs ?? Int64(Date().timeIntervalSince1970)
        _ = try? core.finishTimerSession(sessionId: current.id, status: status, nowSecs: ts)
        self.activeSession = nil
        self.remainingSeconds = 0
        self.recentSessions = (try? core.listTimerSessions(limit: 20)) ?? []
    }

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

    private func startCountdownLoop() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let active = self.activeSession else { return }
                if self.remainingSeconds > 1 {
                    self.remainingSeconds -= 1
                    let mins = self.remainingSeconds / 60
                    let secs = self.remainingSeconds % 60
                    let formatted = String(format: "%02d:%02d", mins, secs)
                    _ = try? self.core.startActivity(
                        activity: FfiActivityInfo(
                            id: "timer-\(active.id)",
                            kind: active.kind,
                            title: formatted,
                            subtitle: active.label
                        ),
                        nowMs: UInt64(Date().timeIntervalSince1970 * 1000.0)
                    )
                } else {
                    self.stopActiveSession(status: "completed")
                }
            }
        }
    }
}
