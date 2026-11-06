import AppKit
import Foundation

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
