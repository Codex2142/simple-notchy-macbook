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
            HStack(spacing: 8) {
                Button {
                    _ = try? adapter.startSession(
                        kind: "pomodoro",
                        label: "Pomodoro 25m",
                        durationSecs: 25 * 60,
                        enableKeepAwake: true
                    )
                } label: {
                    Label("25m Pomodoro", systemImage: "flame.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.orange.opacity(0.25)))
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)

                Button {
                    _ = try? adapter.startSession(
                        kind: "countdown",
                        label: "Quick 5m",
                        durationSecs: 5 * 60,
                        enableKeepAwake: false
                    )
                } label: {
                    Label("5m Timer", systemImage: "timer")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.cyan.opacity(0.25)))
                        .foregroundColor(.cyan)
                }
                .buttonStyle(.plain)

                Button {
                    _ = try? adapter.startSession(
                        kind: "keep_awake",
                        label: "Keep Awake 1h",
                        durationSecs: 60 * 60,
                        enableKeepAwake: true
                    )
                } label: {
                    Label("Keep Awake", systemImage: adapter.isAwakeActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.green.opacity(0.25)))
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)

                if adapter.activeSession != nil {
                    Button {
                        adapter.stopActiveSession(status: "cancelled")
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let active = adapter.activeSession {
                HStack {
                    Text("\(active.label) — \(adapter.remainingSeconds / 60)m \(adapter.remainingSeconds % 60)s remaining")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                    Spacer()
                    if adapter.isAwakeActive {
                        Text("Awake Lock On")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.green)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
            } else {
                Text("Recent Sessions: \(adapter.recentSessions.count)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
}
