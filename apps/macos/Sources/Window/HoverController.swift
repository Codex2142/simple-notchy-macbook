import AppKit
import Foundation
import IslandBridge

/// Coordinates debounced hover-in and hover-out transitions and vertical swipe gestures for the Island.
@MainActor
public final class HoverController {
    public let hoverInDelayMs: UInt64
    public let hoverOutGraceMs: UInt64

    public var onHoverExpandRequested: (() -> Void)?
    public var onHoverExitCollapseRequested: (() -> Void)?
    public var onSwipeGesture: ((SwipeDirection) -> Void)?

    public enum SwipeDirection: Equatable, Sendable {
        case up
        case down
        case left
        case right
    }

    public private(set) var isPointerInside: Bool = false
    private var hoverInTask: Task<Void, Never>?
    private var hoverOutTask: Task<Void, Never>?

    public init(hoverInDelayMs: UInt64 = 130, hoverOutGraceMs: UInt64 = 240) {
        self.hoverInDelayMs = hoverInDelayMs
        self.hoverOutGraceMs = hoverOutGraceMs
    }

    /// Called when the pointer enters the Island tracking area.
    public func pointerEntered() {
        isPointerInside = true
        hoverOutTask?.cancel()
        hoverOutTask = nil

        hoverInTask?.cancel()
        let delayNs = hoverInDelayMs * 1_000_000
        hoverInTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled, let self, self.isPointerInside else { return }
            self.onHoverExpandRequested?()
        }
    }

    /// Called when the pointer exits the Island tracking area.
    public func pointerExited() {
        isPointerInside = false
        hoverInTask?.cancel()
        hoverInTask = nil

        hoverOutTask?.cancel()
        let graceNs = hoverOutGraceMs * 1_000_000
        hoverOutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: graceNs)
            guard !Task.isCancelled, let self, !self.isPointerInside else { return }
            self.onHoverExitCollapseRequested?()
        }
    }

    /// Cancels any pending hover tasks immediately (Rule 3: cancel obsolete transitions safely).
    public func cancelPendingTransitions() {
        hoverInTask?.cancel()
        hoverInTask = nil
        hoverOutTask?.cancel()
        hoverOutTask = nil
    }

    /// Evaluates a screen-space cursor location (`NSEvent.mouseLocation`) against the active geometry and mode
    /// with separate entry and exit hysteresis bounds so the Island never oscillates when expanding or collapsing.
    public func evaluateCursorLocation(
        screenPoint: CGPoint,
        geometry: NotchGeometry,
        mode: FfiIslandMode
    ) {
        let entryRect: CGRect
        switch mode {
        case .hidden, .collapsed:
            entryRect = geometry.collapsedFrame.insetBy(dx: -4, dy: -4)
        case .activity:
            entryRect = geometry.activityFrame.insetBy(dx: -4, dy: -4)
        case .peek:
            entryRect = geometry.peekFrame.insetBy(dx: -6, dy: -6)
        case .expanded, .pinned:
            entryRect = geometry.expandedFrame.insetBy(dx: -14, dy: -14)
        }

        if !isPointerInside {
            if entryRect.contains(screenPoint) {
                pointerEntered()
            }
        } else {
            let exitRect: CGRect
            switch mode {
            case .expanded, .pinned:
                exitRect = geometry.expandedFrame.insetBy(dx: -14, dy: -14)
            case .peek:
                exitRect = geometry.peekFrame.insetBy(dx: -10, dy: -10)
            case .activity:
                exitRect = geometry.activityFrame.insetBy(dx: -10, dy: -10)
            case .collapsed, .hidden:
                exitRect = geometry.collapsedFrame.insetBy(dx: -10, dy: -10)
            }
            if !exitRect.contains(screenPoint) {
                pointerExited()
            }
        }
    }

    /// Processes scroll/swipe deltas on the Island surface.
    public func handleScrollDelta(deltaX: CGFloat, deltaY: CGFloat, threshold: CGFloat = 14.0) {
        if abs(deltaY) >= abs(deltaX) {
            if deltaY > threshold {
                onSwipeGesture?(.down)
            } else if deltaY < -threshold {
                onSwipeGesture?(.up)
            }
        } else {
            if deltaX > threshold {
                onSwipeGesture?(.right)
            } else if deltaX < -threshold {
                onSwipeGesture?(.left)
            }
        }
    }
}
