import AppKit
import IslandBridge

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
