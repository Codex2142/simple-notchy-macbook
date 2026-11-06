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

            // Custom HH:MM:SS Input Card
            HStack(spacing: 8) {
                Text("Custom Duration:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))

                HStack(spacing: 4) {
                    timeInputField(title: "HH", value: Binding(
                        get: { String(format: "%02d", adapter.customHours) },
                        set: { if let v = Int($0), v >= 0, v < 100 { adapter.customHours = v } }
                    ), max: 99)

                    Text(":")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))

                    timeInputField(title: "MM", value: Binding(
                        get: { String(format: "%02d", adapter.customMinutes) },
                        set: { if let v = Int($0), v >= 0, v < 60 { adapter.customMinutes = v } }
                    ), max: 59)

                    Text(":")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))

                    timeInputField(title: "SS", value: Binding(
                        get: { String(format: "%02d", adapter.customSeconds) },
                        set: { if let v = Int($0), v >= 0, v < 60 { adapter.customSeconds = v } }
                    ), max: 59)
                }

                Spacer()

                // Start button for custom input (enabled only if duration > 0)
                Button {
                    adapter.startCustomTimer(
                        hours: adapter.customHours,
                        minutes: adapter.customMinutes,
                        seconds: adapter.customSeconds,
                        enableKeepAwake: false
                    )
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("Start")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(isValidCustomDuration ? Color.green : Color.gray.opacity(0.3))
                    )
                    .foregroundColor(isValidCustomDuration ? .black : .white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(!isValidCustomDuration)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))

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

    private func timeInputField(title: String, value: Binding<String>, max: Int) -> some View {
        TextField(title, text: value)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .frame(width: 26)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.1)))
    }
}
