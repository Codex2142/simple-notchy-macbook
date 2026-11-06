import AppKit
import Combine
import Darwin
import Foundation
import IOKit.ps
import IslandBridge

/// Collects macOS CPU, RAM, Battery, Disk, and Audio Volume metrics using public Mach / IOKit / FileManager APIs
/// with automatic 2-second refresh (PRD FR-005).
@MainActor
public final class SystemMetricsAdapter: ObservableObject {
    @Published public private(set) var telemetry: FfiSystemTelemetry
    @Published public private(set) var diskUsedGb: Double = 0.0
    @Published public private(set) var diskTotalGb: Double = 0.0

    private let core: IslandCore
    private var refreshTask: Task<Void, Never>?
    private var previousCpuTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    public init(core: IslandCore, autoStartRefresh: Bool = false) throws {
        self.core = core
        self.telemetry = try core.currentSystemTelemetry()
        _ = try? sampleHostMetrics()

        if autoStartRefresh {
            startMonitoring(intervalSeconds: 2.0)
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    /// Starts automatic telemetry refresh at the specified interval (default 2.0 seconds).
    /// Ensures only a single polling task exists and throttles when the application is hidden.
    public func startMonitoring(intervalSeconds: Double = 2.0) {
        refreshTask?.cancel()
        let intervalNs = UInt64(max(0.5, intervalSeconds) * 1_000_000_000.0)
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNs)
                guard !Task.isCancelled, let self else { break }
                if NSApp?.isHidden == true {
                    continue
                }
                _ = try? self.sampleHostMetrics()
            }
        }
    }

    public func stopMonitoring() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Reads current macOS host CPU, memory, battery, and disk metrics and pushes them to `IslandCore`.
    @discardableResult
    public func sampleHostMetrics(nowMs: UInt64? = nil) throws -> FfiIslandViewState {
        let cpuPct = sampleCpuUsagePercent()
        let (usedGB, totalGB) = Self.readMemoryUsageGB()
        let (batteryPct, isCharging) = Self.readBatteryState()
        let (dUsed, dTotal) = Self.readDiskUsageGB()
        self.diskUsedGb = dUsed
        self.diskTotalGb = dTotal

        let current = telemetry
        let next = FfiSystemTelemetry(
            cpuUsagePercent: cpuPct,
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

    private func sampleCpuUsagePercent() -> Double {
        guard let ticks = Self.readCpuTicks() else {
            return telemetry.cpuUsagePercent
        }
        defer { previousCpuTicks = ticks }
        guard let prev = previousCpuTicks else {
            let total = Double(ticks.user + ticks.system + ticks.idle + ticks.nice)
            guard total > 0 else { return 0.0 }
            let busy = Double(ticks.user + ticks.system + ticks.nice)
            return ((busy / total) * 1000.0).rounded() / 10.0
        }

        let userDiff = ticks.user >= prev.user ? (ticks.user - prev.user) : 0
        let sysDiff = ticks.system >= prev.system ? (ticks.system - prev.system) : 0
        let idleDiff = ticks.idle >= prev.idle ? (ticks.idle - prev.idle) : 0
        let niceDiff = ticks.nice >= prev.nice ? (ticks.nice - prev.nice) : 0

        let totalDiff = Double(userDiff + sysDiff + idleDiff + niceDiff)
        guard totalDiff > 0 else { return telemetry.cpuUsagePercent }
        let busyDiff = Double(userDiff + sysDiff + niceDiff)
        let pct = min(100.0, max(0.0, (busyDiff / totalDiff) * 100.0))
        return (pct * 10.0).rounded() / 10.0
    }

    private static func readCpuTicks() -> (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return (
            user: UInt64(load.cpu_ticks.0),
            system: UInt64(load.cpu_ticks.1),
            idle: UInt64(load.cpu_ticks.2),
            nice: UInt64(load.cpu_ticks.3)
        )
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

    public static func readDiskUsageGB() -> (usedGB: Double, totalGB: Double) {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let totalBytes = (attrs[.systemSize] as? NSNumber)?.doubleValue,
              let freeBytes = (attrs[.systemFreeSize] as? NSNumber)?.doubleValue
        else {
            return (0.0, 0.0)
        }
        let totalGB = max(1.0, totalBytes / 1_073_741_824.0)
        let usedGB = max(0.0, min(totalGB, (totalBytes - freeBytes) / 1_073_741_824.0))
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
