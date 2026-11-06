import SwiftUI
import IslandBridge
import IslandIntegrations

public struct TimerTabView: View {
    @ObservedObject public var adapter: KeepAwakeAdapter

    public init(adapter: KeepAwakeAdapter) {
        self.adapter = adapter
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Preset pills
            HStack(spacing: 8) {
                Button {
                    adapter.startCustomTimer(hours: 0, minutes: 25, seconds: 0, enableKeepAwake: true)
                } label: {
                    Label("25m Pomodoro", systemImage: "flame.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.orange.opacity(0.25)))
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)

                Button {
                    adapter.startCustomTimer(hours: 0, minutes: 5, seconds: 0, enableKeepAwake: false)
                } label: {
                    Label("5m Quick", systemImage: "timer")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.cyan.opacity(0.25)))
                        .foregroundColor(.cyan)
                }
                .buttonStyle(.plain)

                Button {
                    adapter.startCustomTimer(hours: 1, minutes: 0, seconds: 0, enableKeepAwake: true)
                } label: {
                    Label("1h Keep Awake", systemImage: adapter.isAwakeActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.green.opacity(0.25)))
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)

                Spacer()
            }

            // Modern Native macOS Timer Duration Selector
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    modernTimeUnitSelector(
                        title: "hours",
                        value: adapter.customHours,
                        onIncrement: { adapter.incrementHours(max: 23) },
                        onDecrement: { adapter.decrementHours() },
                        canIncrement: isStepperEnabled && adapter.customHours < 23,
                        canDecrement: isStepperEnabled && adapter.customHours > 0
                    )

                    Text(":")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.bottom, 16)

                    modernTimeUnitSelector(
                        title: "min",
                        value: adapter.customMinutes,
                        onIncrement: { adapter.incrementMinutes() },
                        onDecrement: { adapter.decrementMinutes() },
                        canIncrement: isStepperEnabled && adapter.customMinutes < 59,
                        canDecrement: isStepperEnabled && adapter.customMinutes > 0
                    )

                    Text(":")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.bottom, 16)

                    modernTimeUnitSelector(
                        title: "sec",
                        value: adapter.customSeconds,
                        onIncrement: { adapter.incrementSeconds() },
                        onDecrement: { adapter.decrementSeconds() },
                        canIncrement: isStepperEnabled && adapter.customSeconds < 59,
                        canDecrement: isStepperEnabled && adapter.customSeconds > 0
                    )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.06))
                )

                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        adapter.startCustomTimer(
                            hours: adapter.customHours,
                            minutes: adapter.customMinutes,
                            seconds: adapter.customSeconds,
                            enableKeepAwake: false
                        )
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11))
                            Text("Start Timer")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(canStartCustomTimer ? Color.green : Color.white.opacity(0.1))
                        )
                        .foregroundColor(canStartCustomTimer ? .black : .white.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStartCustomTimer)

                    if !canStartCustomTimer && isStepperEnabled {
                        Text("Set > 00:00:00")
                            .font(.system(size: 9.5))
                            .foregroundColor(.white.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .frame(maxWidth: 120)

                Spacer(minLength: 0)
            }

            // Active or Recent Session Status & Controls (Pause, Resume, Reset)
            if adapter.timerState != .idle {
                activeTimerCard
            } else {
                HStack {
                    Text("Total Recent Sessions: \(adapter.recentSessions.count)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
    }

    private var isValidCustomDuration: Bool {
        (adapter.customHours * 3600 + adapter.customMinutes * 60 + adapter.customSeconds) > 0
    }

    private var isStepperEnabled: Bool {
        adapter.timerState != .running && adapter.timerState != .paused
    }

    private var canStartCustomTimer: Bool {
        isStepperEnabled && isValidCustomDuration
    }

    private var activeTimerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(statusColor)

                Text(adapter.formatHhMmSs(adapter.remainingSeconds))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Text(adapter.timerState == .completed ? "Completed!" : (adapter.timerState == .paused ? "Paused" : "Remaining"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))

                Spacer()

                // Control buttons: Pause / Resume / Reset
                HStack(spacing: 6) {
                    if adapter.timerState == .running {
                        Button {
                            adapter.pauseTimer()
                        } label: {
                            Label("Pause", systemImage: "pause.fill")
                                .font(.system(size: 10.5, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.orange.opacity(0.3)))
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                    } else if adapter.timerState == .paused {
                        Button {
                            adapter.resumeTimer()
                        } label: {
                            Label("Resume", systemImage: "play.fill")
                                .font(.system(size: 10.5, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.green.opacity(0.3)))
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        adapter.resetTimer()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 10.5, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Visual Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 5)

                    Capsule()
                        .fill(statusColor)
                        .frame(width: max(4, geo.size.width * CGFloat(adapter.timerProgress)), height: 5)
                }
            }
            .frame(height: 6)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
    }

    private var statusSymbol: String {
        switch adapter.timerState {
        case .idle: return "timer"
        case .running: return "hourglass"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch adapter.timerState {
        case .idle: return .cyan
        case .running: return .cyan
        case .paused: return .orange
        case .completed: return .green
        }
    }

    private func modernTimeUnitSelector(
        title: String,
        value: Int,
        onIncrement: @escaping () -> Void,
        onDecrement: @escaping () -> Void,
        canIncrement: Bool,
        canDecrement: Bool
    ) -> some View {
        VStack(spacing: 3) {
            Button {
                onIncrement()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9.5, weight: .bold))
                    .frame(width: 30, height: 16)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(canIncrement ? Color.white.opacity(0.12) : Color.clear)
                    )
                    .foregroundColor(canIncrement ? .white.opacity(0.85) : .white.opacity(0.18))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canIncrement)

            Text(String(format: "%02d", value))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 32, height: 24)

            Button {
                onDecrement()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9.5, weight: .bold))
                    .frame(width: 30, height: 16)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(canDecrement ? Color.white.opacity(0.12) : Color.clear)
                    )
                    .foregroundColor(canDecrement ? .white.opacity(0.85) : .white.opacity(0.18))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canDecrement)

            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
                .textCase(.uppercase)
        }
    }
}
