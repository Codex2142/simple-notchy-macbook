import AppKit
import Combine
import IslandBridge

/// Descriptor combining a live display's metrics and computed Dynamic Island geometry.
public struct ConnectedDisplay: Equatable, Sendable {
    public let metrics: ScreenMetrics
    public let geometry: NotchGeometry

    public init(metrics: ScreenMetrics, geometry: NotchGeometry) {
        self.metrics = metrics
        self.geometry = geometry
    }

    public func toFfiProfile(virtualIslandEnabled: Bool = true) -> FfiDisplayProfile {
        FfiDisplayProfile(
            displayUuid: metrics.displayUUID,
            name: metrics.displayName,
            hasHardwareNotch: geometry.hasHardwareNotch,
            notchWidth: Double(geometry.notchRect.width),
            notchHeight: Double(geometry.notchRect.height),
            virtualIslandEnabled: virtualIslandEnabled
        )
    }
}

/// Observes macOS display connections, disconnections, and resolution changes.
@MainActor
public final class DisplayDetector: ObservableObject {
    @Published public private(set) var displays: [ConnectedDisplay] = []
    @Published public private(set) var primaryDisplay: ConnectedDisplay?

    private var screenObserver: NSObjectProtocol?

    public init() {
        refreshDisplays()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDisplays()
            }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    /// Scans `NSScreen.screens` and updates `displays` and `primaryDisplay`.
    public func refreshDisplays() {
        let detected = NSScreen.screens.map { screen in
            let metrics = NotchDetector.extractMetrics(from: screen)
            let geometry = NotchDetector.calculateGeometry(for: metrics)
            return ConnectedDisplay(metrics: metrics, geometry: geometry)
        }
        self.displays = detected
        // Prefer the built-in notched screen if present, otherwise main/first screen
        self.primaryDisplay = detected.first(where: { $0.geometry.hasHardwareNotch }) ?? detected.first
    }
}
