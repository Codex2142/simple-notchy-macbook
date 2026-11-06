import AppKit
import CoreGraphics
import IslandBridge

/// Raw screen metrics decoupled from `NSScreen` so notch math is 100% deterministic and unit-testable.
public struct ScreenMetrics: Equatable, Sendable {
    public let displayUUID: String
    public let displayName: String
    public let frame: CGRect
    public let safeAreaTop: CGFloat
    public let auxiliaryTopLeftWidth: CGFloat?
    public let auxiliaryTopRightWidth: CGFloat?

    public init(
        displayUUID: String,
        displayName: String,
        frame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeftWidth: CGFloat?,
        auxiliaryTopRightWidth: CGFloat?
    ) {
        self.displayUUID = displayUUID
        self.displayName = displayName
        self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeftWidth = auxiliaryTopLeftWidth
        self.auxiliaryTopRightWidth = auxiliaryTopRightWidth
    }
}

/// Computed Dynamic Island geometry for a specific display across all primary Island modes.
public struct NotchGeometry: Equatable, Sendable {
    public let hasHardwareNotch: Bool
    public let notchRect: CGRect
    public let collapsedFrame: CGRect
    public let activityFrame: CGRect
    public let peekFrame: CGRect
    public let expandedFrame: CGRect

    public init(
        hasHardwareNotch: Bool,
        notchRect: CGRect,
        collapsedFrame: CGRect,
        activityFrame: CGRect,
        peekFrame: CGRect,
        expandedFrame: CGRect
    ) {
        self.hasHardwareNotch = hasHardwareNotch
        self.notchRect = notchRect
        self.collapsedFrame = collapsedFrame
        self.activityFrame = activityFrame
        self.peekFrame = peekFrame
        self.expandedFrame = expandedFrame
    }

    /// Returns the target window frame for a given `FfiIslandMode`.
    public func frame(for mode: FfiIslandMode) -> CGRect {
        switch mode {
        case .hidden:
            return CGRect(
                x: collapsedFrame.midX - 40,
                y: collapsedFrame.maxY - 2,
                width: 80,
                height: 2
            )
        case .collapsed:
            return collapsedFrame
        case .activity:
            return activityFrame
        case .peek:
            return peekFrame
        case .expanded, .pinned:
            return expandedFrame
        }
    }
}

public enum NotchDetector {
    /// Calculates Dynamic Island geometry from raw `ScreenMetrics`.
    public static func calculateGeometry(for metrics: ScreenMetrics) -> NotchGeometry {
        let frame = metrics.frame
        let hasNotch = metrics.safeAreaTop > 0

        let notchWidth: CGFloat
        let notchHeight: CGFloat

        if hasNotch {
            if let leftW = metrics.auxiliaryTopLeftWidth,
               let rightW = metrics.auxiliaryTopRightWidth,
               frame.width > (leftW + rightW)
            {
                let cutWidth = frame.width - leftW - rightW
                notchWidth = max(160.0, min(cutWidth, 260.0))
            } else {
                notchWidth = 184.0
            }
            notchHeight = max(28.0, metrics.safeAreaTop)
        } else {
            // Virtual island dimensions for non-notched displays
            notchWidth = 200.0
            notchHeight = 32.0
        }

        let topY = frame.maxY
        let collapsedWidth = hasNotch ? notchWidth + 24.0 : notchWidth
        let collapsedHeight = notchHeight
        let collapsedFrame = topCenteredRect(
            in: frame,
            topY: topY,
            width: collapsedWidth,
            height: collapsedHeight
        )

        let notchRect = topCenteredRect(
            in: frame,
            topY: topY,
            width: notchWidth,
            height: notchHeight
        )

        let activityFrame = topCenteredRect(
            in: frame,
            topY: topY,
            width: collapsedWidth + 110.0,
            height: max(collapsedHeight, 36.0)
        )

        let peekFrame = topCenteredRect(
            in: frame,
            topY: topY,
            width: max(collapsedWidth + 160.0, 360.0),
            height: max(collapsedHeight + 28.0, 62.0)
        )

        let expandedWidth = min(540.0, max(420.0, frame.width * 0.34))
        let expandedHeight: CGFloat = 240.0
        let expandedFrame = topCenteredRect(
            in: frame,
            topY: topY,
            width: expandedWidth,
            height: expandedHeight
        )

        return NotchGeometry(
            hasHardwareNotch: hasNotch,
            notchRect: notchRect,
            collapsedFrame: collapsedFrame,
            activityFrame: activityFrame,
            peekFrame: peekFrame,
            expandedFrame: expandedFrame
        )
    }

    /// Extracts `ScreenMetrics` from a live `NSScreen` and calculates its `NotchGeometry`.
    @MainActor
    public static func detect(for screen: NSScreen) -> NotchGeometry {
        let metrics = extractMetrics(from: screen)
        return calculateGeometry(for: metrics)
    }

    @MainActor
    public static func extractMetrics(from screen: NSScreen) -> ScreenMetrics {
        let uuid = resolveDisplayUUID(for: screen)
        let topSafe = screen.safeAreaInsets.top
        let leftAux = screen.auxiliaryTopLeftArea?.width
        let rightAux = screen.auxiliaryTopRightArea?.width

        return ScreenMetrics(
            displayUUID: uuid,
            displayName: screen.localizedName,
            frame: screen.frame,
            safeAreaTop: topSafe,
            auxiliaryTopLeftWidth: leftAux,
            auxiliaryTopRightWidth: rightAux
        )
    }

    @MainActor
    public static func resolveDisplayUUID(for screen: NSScreen) -> String {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return "UNKNOWN-DISPLAY"
        }
        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        if let uuidRef = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let cfStr = CFUUIDCreateString(nil, uuidRef)
        {
            return cfStr as String
        }
        return "DISPLAY-\(displayID)"
    }

    private static func topCenteredRect(
        in screenFrame: CGRect,
        topY: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> CGRect {
        let originX = (screenFrame.origin.x + (screenFrame.width - width) / 2.0).rounded()
        let originY = (topY - height).rounded()
        return CGRect(x: originX, y: originY, width: width.rounded(), height: height.rounded())
    }
}
