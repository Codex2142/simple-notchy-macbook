import SwiftUI
import IslandBridge
import IslandIntegrations

public struct SystemMetricsView: View {
    @ObservedObject public var adapter: SystemMetricsAdapter

    public init(adapter: SystemMetricsAdapter) {
        self.adapter = adapter
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                metricCard(
                    title: "Memory",
                    value: String(format: "%.1f / %.0f GB", adapter.telemetry.memoryUsedGb, adapter.telemetry.memoryTotalGb),
                    symbol: "memorychip",
                    tint: .cyan
                )

                metricCard(
                    title: "Battery",
                    value: "\(adapter.telemetry.batteryPercent)% \(adapter.telemetry.isCharging ? "⚡︎" : "")",
                    symbol: adapter.telemetry.isCharging ? "battery.100.bolt" : "battery.75",
                    tint: .green
                )

                metricCard(
                    title: "Volume",
                    value: adapter.telemetry.isMuted ? "Muted" : "\(adapter.telemetry.volumePercent)%",
                    symbol: adapter.telemetry.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    tint: .orange
                )
            }

            HStack {
                Button("Refresh Telemetry") {
                    _ = try? adapter.sampleHostMetrics()
                }
                .font(.system(size: 11))

                Spacer()
            }
        }
    }

    private func metricCard(title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(tint)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
            }
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }
}
