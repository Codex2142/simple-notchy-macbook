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
            HStack(spacing: 10) {
                metricCard(
                    title: "CPU Load",
                    value: String(format: "%.1f%%", adapter.telemetry.cpuUsagePercent),
                    symbol: "cpu",
                    tint: .purple
                )

                metricCard(
                    title: "Memory",
                    value: String(format: "%.1f / %.0f GB", adapter.telemetry.memoryUsedGb, adapter.telemetry.memoryTotalGb),
                    symbol: "memorychip",
                    tint: .cyan
                )
            }

            HStack(spacing: 10) {
                metricCard(
                    title: "Battery",
                    value: "\(adapter.telemetry.batteryPercent)% \(adapter.telemetry.isCharging ? "⚡︎ Charging" : "On Battery")",
                    symbol: adapter.telemetry.isCharging ? "battery.100.bolt" : "battery.75",
                    tint: .green
                )

                metricCard(
                    title: "Disk",
                    value: adapter.diskTotalGb > 0
                        ? String(format: "%.0f / %.0f GB", adapter.diskUsedGb, adapter.diskTotalGb)
                        : "\(adapter.telemetry.volumePercent)% Vol",
                    symbol: "internaldrive",
                    tint: .orange
                )
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("Live Telemetry • Auto-refreshes every 2s")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
            }
        }
    }

    private func metricCard(title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(tint)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.68))
            }
            Text(value)
                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}
