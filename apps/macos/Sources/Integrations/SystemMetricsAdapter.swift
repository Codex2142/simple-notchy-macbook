import Combine
import Darwin
import Foundation
import IOKit.ps
import IslandBridge

/// Collects macOS CPU, RAM, Battery, and Audio Volume metrics using public Mach / IOKit APIs
/// without background polling while the Island is collapsed (PRD FR-005 & Section 4 `<1%` CPU target).
@MainActor
public final class SystemMetricsAdapter: ObservableObject {
    @Published public private(set) var telemetry: FfiSystemTelemetry

    private let core: IslandCore

    public init(core: IslandCore) throws {
        self.core = core
        self.telemetry = try core.currentSystemTelemetry()
        _ = try? sampleHostMetrics()
    }

    /// Reads current macOS host memory and battery metrics and pushes them to `IslandCore`.
    @discardableResult
    public func sampleHostMetrics(nowMs: UInt64? = nil) throws -> FfiIslandViewState {
        let (usedGB, totalGB) = Self.readMemoryUsageGB()
        let (batteryPct, isCharging) = Self.readBatteryState()
        let current = telemetry

        let next = FfiSystemTelemetry(
            cpuUsagePercent: current.cpuUsagePercent,
            memoryUsedGb: usedGB,
            memoryTotalGb: totalGB,
            batteryPercent: batteryPct,
            isCharging: isCharging,
            volumePercent: current.volumePercent,
            isMuted: current.isMuted
        )
        return try reportTelemetry(next, nowMs: nowMs)
    }

    /// Reports a volume or mute change, triggering a `volume_hud` Peek in the Dynamic Island.
    @discardableResult
    public func reportVolumeChange(
        volumePercent: UInt32,
        isMuted: Bool,
        nowMs: UInt64? = nil
    ) throws -> FfiIslandViewState {
        var next = telemetry
        next.volumePercent = min(100, volumePercent)
        next.isMuted = isMuted
        return try reportTelemetry(next, nowMs: nowMs)
    }

    @discardableResult
    public func reportTelemetry(_ next: FfiSystemTelemetry, nowMs: UInt64? = nil) throws -> FfiIslandViewState {
        let ts = nowMs ?? UInt64(Date().timeIntervalSince1970 * 1000.0)
        let state = try core.updateSystemTelemetry(metrics: next, nowMs: ts)
        self.telemetry = try core.currentSystemTelemetry()
        return state
    }

    public static func readMemoryUsageGB() -> (usedGB: Double, totalGB: Double) {
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        let totalGB = max(1.0, totalBytes / 1_073_741_824.0)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return (usedGB: totalGB * 0.4, totalGB: totalGB)
        }

        let pageSize = Double(vm_kernel_page_size)
        let activeBytes = Double(stats.active_count + stats.wire_count + stats.compressor_page_count) * pageSize
        let usedGB = min(totalGB, max(0.1, activeBytes / 1_073_741_824.0))
        return (usedGB: (usedGB * 10).rounded() / 10.0, totalGB: (totalGB * 10).rounded() / 10.0)
    }

    public static func readBatteryState() -> (percent: UInt32, isCharging: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue() as? [String: Any]
        else {
            return (100, true)
        }

        let currentCap = (desc[kIOPSCurrentCapacityKey as String] as? Int) ?? 100
        let maxCap = max(1, (desc[kIOPSMaxCapacityKey as String] as? Int) ?? 100)
        let pct = UInt32(max(0, min(100, (currentCap * 100) / maxCap)))
        let powerSource = (desc[kIOPSPowerSourceStateKey as String] as? String) ?? ""
        let isCharging = (powerSource == kIOPSACPowerValue)
        return (pct, isCharging)
    }
}
