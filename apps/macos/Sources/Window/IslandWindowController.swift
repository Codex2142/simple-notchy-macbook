import AppKit
import Combine
import IslandBridge
import QuartzCore
import SwiftUI

/// Bridges UniFFI `IslandStateListener` callbacks onto the Swift `@MainActor`.
private final class FfiStateListenerBridge: IslandStateListener {
    private let onUpdate: @Sendable (FfiIslandViewState) -> Void

    init(onUpdate: @escaping @Sendable (FfiIslandViewState) -> Void) {
        self.onUpdate = onUpdate
    }

    func onStateChanged(newState: FfiIslandViewState) {
        onUpdate(newState)
    }
}

/// Primary tabs available inside the expanded Dynamic Island.
public enum IslandTab: String, CaseIterable, Identifiable, Sendable {
    case home = "Overview"
    case clipboard = "Clipboard"
    case timer = "Timer"
    case notes = "Notes"
    case shelf = "Shelf"
    case system = "System"

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .home: return "sparkles"
        case .clipboard: return "doc.on.clipboard"
        case .timer: return "timer"
        case .notes: return "note.text"
        case .shelf: return "tray.and.arrow.down"
        case .system: return "cpu"
        }
    }
}

/// Coordinates the `IslandPanel`, `DisplayDetector`, `HoverController`, and `IslandCore` state machine.
@MainActor
public final class IslandWindowController: ObservableObject {
    @Published public private(set) var viewState: FfiIslandViewState
    @Published public private(set) var activeGeometry: NotchGeometry?
    @Published public var selectedTab: IslandTab = .home

    public let core: IslandCore
    public let displayDetector: DisplayDetector
    public let hoverController: HoverController
    public private(set) var panel: IslandPanel?

    private var cancellables = Set<AnyCancellable>()
    private var peekAutoCollapseTask: Task<Void, Never>?

    public init(
        core: IslandCore,
        displayDetector: DisplayDetector? = nil,
        hoverController: HoverController? = nil
    ) throws {
        let resolvedDisplayDetector = displayDetector ?? DisplayDetector()
        let resolvedHoverController = hoverController ?? HoverController()
        self.core = core
        self.displayDetector = resolvedDisplayDetector
        self.hoverController = resolvedHoverController
        self.viewState = try core.currentState()
        self.activeGeometry = resolvedDisplayDetector.primaryDisplay?.geometry

        bindCoreEvents()
        bindHoverAndGestures()
        bindDisplayChanges()
    }

    /// Creates and displays the floating `IslandPanel` with the provided SwiftUI root view.
    public func attachRootView<Content: View>(_ rootView: Content) {
        let initialGeometry = activeGeometry ?? NotchDetector.calculateGeometry(
            for: ScreenMetrics(
                displayUUID: "DEFAULT",
                displayName: "Main Display",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                safeAreaTop: 37,
                auxiliaryTopLeftWidth: 664,
                auxiliaryTopRightWidth: 664
            )
        )
        let targetFrame = initialGeometry.frame(for: viewState.mode)
        let islandPanel = IslandPanel(contentRect: targetFrame)
        islandPanel.contentView = NSHostingView(rootView: rootView)
        islandPanel.orderFrontRegardless()
        self.panel = islandPanel
    }

    public func handlePointerEntered() {
        hoverController.pointerEntered()
    }

    public func handlePointerExited() {
        _ = try? core.setInteracting(interacting: false, nowMs: Self.nowMs())
        hoverController.pointerExited()
    }

    public func toggleExpandedOrPinned() {
        let now = Self.nowMs()
        switch viewState.mode {
        case .collapsed, .activity, .peek:
            _ = try? core.expand(nowMs: now)
        case .expanded:
            _ = try? core.pin(nowMs: now)
        case .pinned:
            _ = try? core.unpin(nowMs: now)
        case .hidden:
            _ = try? core.setHidden(hidden: false, nowMs: now)
        }
    }

    public func togglePin() {
        let now = Self.nowMs()
        if viewState.mode == .pinned {
            _ = try? core.unpin(nowMs: now)
        } else {
            _ = try? core.pin(nowMs: now)
        }
    }

    public func collapseNow() {
        let now = Self.nowMs()
        if viewState.mode == .pinned {
            _ = try? core.unpin(nowMs: now)
        }
        _ = try? core.setInteracting(interacting: false, nowMs: now)
        _ = try? core.tryAutoCollapse(expectedEpoch: nil, nowMs: now)
    }

    private func bindCoreEvents() {
        let bridge = FfiStateListenerBridge { [weak self] newState in
            Task { @MainActor [weak self] in
                self?.applyViewState(newState)
            }
        }
        core.addStateListener(listener: bridge)
    }

    private func bindHoverAndGestures() {
        hoverController.onHoverExpandRequested = { [weak self] in
            guard let self else { return }
            _ = try? self.core.expand(nowMs: Self.nowMs())
        }

        hoverController.onHoverExitCollapseRequested = { [weak self] in
            guard let self else { return }
            let epoch = self.viewState.transitionEpoch
            _ = try? self.core.tryAutoCollapse(expectedEpoch: epoch, nowMs: Self.nowMs())
        }

        hoverController.onSwipeGesture = { [weak self] direction in
            guard let self else { return }
            let now = Self.nowMs()
            switch direction {
            case .down:
                _ = try? self.core.expand(nowMs: now)
            case .up:
                _ = try? self.core.setInteracting(interacting: false, nowMs: now)
                _ = try? self.core.tryAutoCollapse(expectedEpoch: nil, nowMs: now)
            case .left, .right:
                break
            }
        }
    }

    private func bindDisplayChanges() {
        displayDetector.$primaryDisplay
            .sink { [weak self] display in
                guard let self, let display else { return }
                self.activeGeometry = display.geometry
                try? self.core.registerDisplayProfile(profile: display.toFfiProfile())
                self.animatePanelToCurrentMode(geometry: display.geometry, mode: self.viewState.mode)
            }
            .store(in: &cancellables)
    }

    private func applyViewState(_ newState: FfiIslandViewState) {
        self.viewState = newState
        if let geometry = activeGeometry {
            animatePanelToCurrentMode(geometry: geometry, mode: newState.mode)
        }

        peekAutoCollapseTask?.cancel()
        if newState.mode == .peek {
            let epoch = newState.transitionEpoch
            peekAutoCollapseTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_800_000_000)
                guard !Task.isCancelled, let self else { return }
                _ = try? self.core.tryAutoCollapse(expectedEpoch: epoch, nowMs: Self.nowMs())
            }
        }
    }

    private func animatePanelToCurrentMode(geometry: NotchGeometry, mode: FfiIslandMode) {
        guard let panel else { return }
        let targetFrame = geometry.frame(for: mode)
        panel.level = WindowLevelManager.windowLevel(for: mode)
        panel.allowKeyFocus = (mode == .expanded || mode == .pinned)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            panel.animator().setFrame(targetFrame, display: true)
        }
    }

    public static func nowMs() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1000.0)
    }
}
