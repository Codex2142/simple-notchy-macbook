import SwiftUI
import IslandBridge
import IslandWindow
import IslandIntegrations
import IslandFeatures

/// Primary SwiftUI shell for the Dynamic Island across Collapsed, Activity, Peek, and Expanded/Pinned modes.
public struct IslandRootView: View {
    @ObservedObject public var controller: IslandWindowController
    @ObservedObject public var pasteboardMonitor: PasteboardMonitor

    public init(controller: IslandWindowController, pasteboardMonitor: PasteboardMonitor) {
        self.controller = controller
        self.pasteboardMonitor = pasteboardMonitor
    }

    public var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                )

            contentForMode
                .padding(.horizontal, isExpandedLike ? 16 : 10)
                .padding(.vertical, isExpandedLike ? 12 : 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onHover { inside in
            if inside {
                controller.handlePointerEntered()
            } else {
                controller.handlePointerExited()
            }
        }
        .onTapGesture {
            if !isExpandedLike {
                controller.toggleExpandedOrPinned()
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: controller.viewState.mode)
    }

    private var isExpandedLike: Bool {
        controller.viewState.mode == .expanded || controller.viewState.mode == .pinned
    }

    private var cornerRadius: CGFloat {
        switch controller.viewState.mode {
        case .hidden:
            return 2
        case .collapsed, .activity:
            return 16
        case .peek:
            return 20
        case .expanded, .pinned:
            return 26
        }
    }

    @ViewBuilder
    private var contentForMode: some View {
        switch controller.viewState.mode {
        case .hidden:
            EmptyView()
        case .collapsed:
            collapsedBar
        case .activity:
            activityBar
        case .peek:
            peekBar
        case .expanded, .pinned:
            expandedPanel
        }
    }

    private var collapsedBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green.opacity(0.85))
                .frame(width: 6, height: 6)
            Spacer(minLength: 0)
            Image(systemName: "waveform")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.75))
        }
    }

    private var activityBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.orange)
            Text(controller.viewState.activeActivity?.title ?? "Active")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
            Spacer(minLength: 0)
            Text(controller.viewState.activeActivity?.subtitle ?? "")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private var peekBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.viewState.activePeek?.title ?? "Notification")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let sub = controller.viewState.activePeek?.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(IslandTab.allCases) { tab in
                    Button {
                        controller.selectedTab = tab
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tab.symbolName)
                                .font(.system(size: 11, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(controller.selectedTab == tab ? Color.white.opacity(0.18) : Color.clear)
                        )
                        .foregroundColor(controller.selectedTab == tab ? .white : .white.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    controller.togglePin()
                } label: {
                    Image(systemName: controller.viewState.mode == .pinned ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(controller.viewState.mode == .pinned ? .yellow : .white.opacity(0.7))
                        .padding(5)
                }
                .buttonStyle(.plain)
                .help(controller.viewState.mode == .pinned ? "Unpin Island" : "Pin Island")
            }

            Divider()
                .background(Color.white.opacity(0.12))

            if controller.selectedTab == .clipboard {
                ClipboardTabView(monitor: pasteboardMonitor)
            } else {
                Spacer(minLength: 0)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Project Island — \(controller.selectedTab.rawValue)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Text(statusLine)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var statusLine: String {
        let hasNotch = controller.activeGeometry?.hasHardwareNotch ?? false
        let displayType = hasNotch ? "Hardware Notch" : "Virtual Island"
        return "\(displayType) • Mode: \(String(describing: controller.viewState.mode))"
    }
}
