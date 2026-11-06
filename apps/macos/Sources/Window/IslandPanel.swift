import AppKit
import IslandBridge
import SwiftUI

/// Manages window levels across normal, fullscreen, and pinned Island states (PRD Section 6).
public enum WindowLevelManager {
    public static func windowLevel(for mode: FfiIslandMode) -> NSWindow.Level {
        switch mode {
        case .hidden:
            return .normal
        case .collapsed, .activity:
            return NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        case .peek, .expanded, .pinned:
            return NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        }
    }
}

/// Custom `NSHostingView` that restricts mouse hit-testing to the active Dynamic Island pill size,
/// so clicks on the transparent area around the collapsed/peek pill pass through to the menu bar and apps below.
public final class IslandHostingView<Content: View>: NSHostingView<Content> {
    public var activeHitSize: CGSize = .zero

    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override public var mouseDownCanMoveWindow: Bool {
        false
    }

    override public func hitTest(_ point: NSPoint) -> NSView? {
        guard activeHitSize.width > 0, activeHitSize.height > 0 else {
            return super.hitTest(point)
        }
        let pillX = (bounds.width - activeHitSize.width) / 2.0
        let pillY = isFlipped ? 0.0 : (bounds.height - activeHitSize.height)
        let activeRect = CGRect(
            x: pillX - 6.0,
            y: pillY - (isFlipped ? 0.0 : 6.0),
            width: activeHitSize.width + 12.0,
            height: activeHitSize.height + 6.0
        )
        guard activeRect.contains(point) else {
            return nil
        }
        return super.hitTest(point)
    }
}

/// Non-activating floating AppKit panel that sits flush with the MacBook notch or top screen edge.
public final class IslandPanel: NSPanel {
    public var allowKeyFocus: Bool = false

    public init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = WindowLevelManager.windowLevel(for: .collapsed)
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.acceptsMouseMovedEvents = true
        self.hidesOnDeactivate = false
        self.animationBehavior = .none
    }

    override public var canBecomeKey: Bool {
        allowKeyFocus
    }

    override public var canBecomeMain: Bool {
        false
    }
}
