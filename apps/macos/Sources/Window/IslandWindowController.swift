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

    public var moduleId: String {
        switch self {
        case .home: return "media"
        case .clipboard: return "clipboard"
        case .timer: return "timer"
        case .notes: return "notes"
        case .shelf: return "shelf"
        case .system: return "system"
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
    private var cursorWatchTask: Task<Void, Never>?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var updateHitSizeClosure: ((CGSize) -> Void)?
    private var spaceObserver: NSObjectProtocol?
    private var occlusionObserver: NSObjectProtocol?

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
        bindSpaceEvents()
    }

    deinit {
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
    }

    /// Creates and displays the floating `IslandPanel` with the provided SwiftUI root view.
    /// Keeps the `NSPanel` at a stable `expandedFrame` canvas and uses `IslandHostingView.hitTest(_:)`
    /// for click-through outside the active pill so the window never thrashes `NSTrackingArea` on hover.
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
        self.activeGeometry = initialGeometry

        let islandPanel = IslandPanel(contentRect: initialGeometry.expandedFrame)
        let hostingView = IslandHostingView(rootView: rootView)
        hostingView.activeHitSize = initialGeometry.frame(for: viewState.mode).size
        self.updateHitSizeClosure = { [weak hostingView] newSize in
            hostingView?.activeHitSize = newSize
        }
        islandPanel.contentView = hostingView
        islandPanel.orderFrontRegardless()
        self.panel = islandPanel

        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: islandPanel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let panel = self.panel else { return }
                // Hide panel if window is not on active space to prevent dragging across desktop transitions
                panel.alphaValue = panel.isOnActiveSpace ? 1.0 : 0.0
            }
        }

        installMouseMonitors()
    }

    public func handlePointerEntered() {
        _ = try? core.setInteracting(interacting: true, nowMs: Self.nowMs())
        hoverController.pointerEntered()
    }

    public func handlePointerExited() {
        // Guard against spurious SwiftUI `.onHover(false)` callbacks fired when the pill layout expands under the cursor.
        if let geometry = activeGeometry {
            let mouseLoc = NSEvent.mouseLocation
            let activeExitRect = geometry.hitTestRect(for: viewState.mode, hysteresis: 14)
            if activeExitRect.contains(mouseLoc) {
                return
            }
        }
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
            if let geometry = self.activeGeometry {
                let mouseLoc = NSEvent.mouseLocation
                if geometry.hitTestRect(for: self.viewState.mode, hysteresis: 14).contains(mouseLoc) {
                    return
                }
            }
            _ = try? self.core.setInteracting(interacting: false, nowMs: Self.nowMs())
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

    private func bindSpaceEvents() {
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleActiveSpaceChanged()
            }
        }
    }

    public func handleActiveSpaceChanged() {
        displayDetector.refreshDisplays()
        guard let panel else { return }
        if let geometry = activeGeometry {
            panel.setFrame(geometry.expandedFrame, display: true)
        }
        panel.orderFrontRegardless()
        panel.alphaValue = 1.0
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
        let activeSize = geometry.frame(for: mode).size
        updateHitSizeClosure?(activeSize)

        guard let panel else { return }
        panel.level = WindowLevelManager.windowLevel(for: mode)
        panel.allowKeyFocus = (mode == .expanded || mode == .pinned)

        if panel.frame != geometry.expandedFrame {
            panel.setFrame(geometry.expandedFrame, display: true)
        }
    }

    private func installMouseMonitors() {
        if localMouseMonitor == nil {
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .mouseEntered, .mouseExited]
            ) { [weak self] event in
                self?.checkMouseLocation()
                return event
            }
        }
        if globalMouseMonitor == nil {
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged]
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.checkMouseLocation()
                }
            }
        }
        cursorWatchTask?.cancel()
        cursorWatchTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled, let self else { break }
                self.checkMouseLocation()
            }
        }
    }

    private func checkMouseLocation() {
        guard let geometry = activeGeometry else { return }
        let mouseLoc = NSEvent.mouseLocation
        hoverController.evaluateCursorLocation(
            screenPoint: mouseLoc,
            geometry: geometry,
            mode: viewState.mode
        )
    }

    public static func nowMs() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1000.0)
    }
}
