import SwiftUI
import IslandBridge
import IslandWindow
import IslandIntegrations
import IslandFeatures

/// Primary SwiftUI shell for the Dynamic Island across Collapsed, Activity, Peek, and Expanded/Pinned modes.
/// Dynamically respects the physical hardware notch cutout (`notchSafeTopInset` & `notchRect.width`) on MacBook Air M2 / Pro.
public struct IslandRootView: View {
    @ObservedObject public var controller: IslandWindowController
    @ObservedObject public var pasteboardMonitor: PasteboardMonitor
    @ObservedObject public var keepAwakeAdapter: KeepAwakeAdapter
    @ObservedObject public var mediaAdapter: MediaAdapter
    @ObservedObject public var systemMetricsAdapter: SystemMetricsAdapter
    @ObservedObject public var notesShelfStore: NotesShelfStore

    public init(
        controller: IslandWindowController,
        pasteboardMonitor: PasteboardMonitor,
        keepAwakeAdapter: KeepAwakeAdapter,
        mediaAdapter: MediaAdapter,
        systemMetricsAdapter: SystemMetricsAdapter,
        notesShelfStore: NotesShelfStore
    ) {
        self.controller = controller
        self.pasteboardMonitor = pasteboardMonitor
        self.keepAwakeAdapter = keepAwakeAdapter
        self.mediaAdapter = mediaAdapter
        self.systemMetricsAdapter = systemMetricsAdapter
        self.notesShelfStore = notesShelfStore
    }

    public var body: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                // Pure opaque black (same as the physical notch), flat top, rounded bottom corners only.
                NotchShape(topRadius: 0, bottomRadius: cornerRadius)
                    .fill(Color.black)

                contentForMode

                // Subtle bottom progress bar for active timer when Island is not hovered / not expanded
                if !isExpandedLike && isTimerActive {
                    collapsedTimerProgressBar
                }
            }
            .frame(width: activePillSize.width, height: activePillSize.height, alignment: .top)
            .clipShape(NotchShape(topRadius: 0, bottomRadius: cornerRadius))
            .onHover { inside in
                if inside {
                    controller.handlePointerEntered()
                } else {
                    controller.handlePointerExited()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .animation(.spring(response: 0.30, dampingFraction: 0.84), value: controller.viewState.mode)
    }

    private var collapsedTimerProgressBar: some View {
        VStack(spacing: 0) {
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 2.2)

                    Rectangle()
                        .fill(
                            keepAwakeAdapter.timerState == .completed ? Color.green :
                            (keepAwakeAdapter.timerState == .paused ? Color.orange : Color.cyan)
                        )
                        .frame(width: max(0, geo.size.width * CGFloat(keepAwakeAdapter.timerProgress)), height: 2.2)
                }
            }
            .frame(height: 2.2)
        }
    }

    private var isExpandedLike: Bool {
        controller.viewState.mode == .expanded || controller.viewState.mode == .pinned
    }

    private var isTimerActive: Bool {
        keepAwakeAdapter.timerState == .running || keepAwakeAdapter.timerState == .paused || keepAwakeAdapter.timerState == .completed
    }

    private var hasHardwareNotch: Bool {
        controller.activeGeometry?.hasHardwareNotch ?? true
    }

    /// Dynamic height of the physical camera housing on notched MacBooks (e.g., MacBook Air M2), or 0 on external monitors.
    private var notchSafeTopInset: CGFloat {
        controller.activeGeometry?.notchSafeTopInset ?? 37.0
    }

    /// Dynamic width of the physical camera housing on notched MacBooks.
    private var notchCutoutWidth: CGFloat {
        guard hasHardwareNotch else { return 0.0 }
        return controller.activeGeometry?.notchRect.width ?? 184.0
    }

    private var activePillSize: CGSize {
        if isTimerActive && !isExpandedLike {
            if let geometry = controller.activeGeometry {
                return geometry.frame(for: .collapsed).size
            }
            return CGSize(width: 296, height: 37)
        }
        if let geometry = controller.activeGeometry {
            return geometry.frame(for: controller.viewState.mode).size
        }
        switch controller.viewState.mode {
        case .hidden:
            return CGSize(width: 80, height: 2)
        case .collapsed:
            return CGSize(width: 296, height: 37)
        case .activity:
            return CGSize(width: 426, height: 38)
        case .peek:
            return CGSize(width: 456, height: 105)
        case .expanded, .pinned:
            return CGSize(width: 560, height: 332)
        }
    }

    private var cornerRadius: CGFloat {
        if isTimerActive && !isExpandedLike {
            return 18
        }
        switch controller.viewState.mode {
        case .hidden:
            return 2
        case .collapsed, .activity:
            return 18
        case .peek:
            return 22
        case .expanded, .pinned:
            return 26
        }
    }

    @ViewBuilder
    private var contentForMode: some View {
        switch controller.viewState.mode {
        case .hidden:
            EmptyView()
        case .collapsed, .activity:
            if isTimerActive {
                Color.clear
                    .frame(width: activePillSize.width, height: activePillSize.height)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        controller.toggleExpandedOrPinned()
                    }
            } else if controller.viewState.mode == .activity {
                activityBar
                    .contentShape(Rectangle())
                    .onTapGesture {
                        controller.toggleExpandedOrPinned()
                    }
            } else {
                collapsedBar
                    .contentShape(Rectangle())
                    .onTapGesture {
                        controller.toggleExpandedOrPinned()
                    }
            }
        case .peek:
            peekBar
                .contentShape(Rectangle())
                .onTapGesture {
                    controller.toggleExpandedOrPinned()
                }
        case .expanded, .pinned:
            expandedPanel
        }
    }

    // MARK: - Collapsed Island (Circular Spotify Artwork + Progressive Border outside Hardware Notch)

    @ViewBuilder
    private var collapsedBar: some View {
        if isTimerActive {
            // When timer is active: prioritize timer by hiding Spotify information completely.
            // Only the bottom timer progress bar is displayed on the notch.
            Color.clear
                .frame(width: activePillSize.width, height: activePillSize.height)
        } else {
            let wingWidth = controller.activeGeometry?.wingWidth(for: .collapsed) ?? 56.0
            HStack(spacing: 0) {
                // Left Wing (completely to the left of the physical MacBook Air M2 notch)
                HStack(spacing: 6) {
                    collapsedCircularArtworkWithProgress
                    Spacer(minLength: 0)
                }
                .padding(.leading, 10)
                .frame(width: wingWidth, height: activePillSize.height, alignment: .leading)

                // Center Hardware Notch Cutout Clearance
                if hasHardwareNotch {
                    Spacer(minLength: 0)
                        .frame(width: notchCutoutWidth)
                } else if let track = mediaAdapter.nowPlaying, track.isPlaying {
                    Text(track.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                } else {
                    Spacer(minLength: 0)
                }

                // Right Wing (completely to the right of the physical MacBook Air M2 notch)
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Image(systemName: mediaAdapter.nowPlaying?.isPlaying == true ? "waveform.circle.fill" : "waveform")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(mediaAdapter.nowPlaying?.isPlaying == true ? .green : .white.opacity(0.75))
                }
                .padding(.trailing, 10)
                .frame(width: wingWidth, height: activePillSize.height, alignment: .trailing)
            }
            .frame(width: activePillSize.width, height: activePillSize.height)
        }
    }

    /// Circular Spotify album artwork thumbnail surrounded by a smooth progressive circular playback border.
    private var collapsedCircularArtworkWithProgress: some View {
        let progress = CGFloat(max(0.0, min(1.0, mediaAdapter.playbackProgress)))
        let isPlaying = mediaAdapter.nowPlaying?.isPlaying == true
        let trackIdentity = "\(mediaAdapter.nowPlaying?.title ?? "")::\(mediaAdapter.nowPlaying?.artist ?? "")"

        return ZStack {
            // Background track ring
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 2.2)
                .frame(width: 25, height: 25)

            // Progressive playback border synchronized with Spotify position / duration
            Circle()
                .trim(from: 0.0, to: progress)
                .stroke(
                    isPlaying ? Color.green : Color.white.opacity(0.55),
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 25, height: 25)
                .animation(.linear(duration: 0.10), value: progress)

            // Inner circular Spotify artwork
            if let urlStr = mediaAdapter.nowPlaying?.artworkUrl,
               !urlStr.isEmpty,
               let url = URL(string: urlStr)
            {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 19, height: 19)
                            .clipShape(Circle())
                    default:
                        fallbackCollapsedDisc(isPlaying: isPlaying)
                    }
                }
                .id(trackIdentity)
            } else {
                fallbackCollapsedDisc(isPlaying: isPlaying)
            }
        }
        .frame(width: 26, height: 26)
    }

    private func fallbackCollapsedDisc(isPlaying: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isPlaying ? Color.green.opacity(0.25) : Color.white.opacity(0.12))
                .frame(width: 19, height: 19)
            Image(systemName: isPlaying ? "music.note" : "sparkle")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(isPlaying ? .green : .white.opacity(0.8))
        }
    }

    // MARK: - Activity Mode (Wings flank the physical notch so no text is covered)

    private var activityBar: some View {
        let wingWidth = controller.activeGeometry?.wingWidth(for: .activity) ?? 120.0
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
                Text(controller.viewState.activeActivity?.title ?? "Active")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.leading, 12)
            .frame(width: wingWidth, height: activePillSize.height, alignment: .leading)

            if hasHardwareNotch {
                Spacer(minLength: 0)
                    .frame(width: notchCutoutWidth)
            } else {
                Spacer(minLength: 8)
            }

            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Text(controller.viewState.activeActivity?.subtitle ?? "")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .padding(.trailing, 12)
            .frame(width: wingWidth, height: activePillSize.height, alignment: .trailing)
        }
        .frame(width: activePillSize.width, height: activePillSize.height)
    }

    // MARK: - Peek Mode (Content placed below `notchSafeTopInset` so text is never clipped 30% vertically)

    private var peekBar: some View {
        VStack(spacing: 0) {
            if hasHardwareNotch {
                Spacer(minLength: 0)
                    .frame(height: notchSafeTopInset)
            }

            HStack(spacing: 12) {
                collapsedCircularArtworkWithProgress

                VStack(alignment: .leading, spacing: 3) {
                    Text(controller.viewState.activePeek?.title ?? "Notification")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)

                    if let sub = controller.viewState.activePeek?.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                if let snap = mediaAdapter.lyricsSnapshot,
                   snap.hasSyncedLyrics,
                   !snap.currentLine.isEmpty
                {
                    Text(snap.currentLine)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.green)
                        .lineLimit(1)
                        .frame(maxWidth: 170, alignment: .trailing)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    // MARK: - Expanded / Pinned Panel (Notch Safe Header + Full Unobstructed Tab Bar Below Notch)

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top zone flanking the physical MacBook Air M2 notch so interactive tabs sit 100% below the camera housing
            if hasHardwareNotch {
                let wingWidth = controller.activeGeometry?.wingWidth(for: controller.viewState.mode) ?? 170.0
                HStack(spacing: 0) {
                    HStack(spacing: 8) {
                        collapsedCircularArtworkWithProgress
                        if let track = mediaAdapter.nowPlaying {
                            Text(track.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.88))
                                .lineLimit(1)
                        } else {
                            Text("Project Island")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: max(80, wingWidth - 16), alignment: .leading)

                    // Physical Notch Cutout Space
                    Spacer(minLength: 0)
                        .frame(width: notchCutoutWidth)

                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        Text(String(format: "CPU %.0f%%", systemMetricsAdapter.telemetry.cpuUsagePercent))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(1)

                        pinButton
                    }
                    .frame(width: max(80, wingWidth - 16), alignment: .trailing)
                }
                .frame(height: max(32, notchSafeTopInset))
            }

            // Full Interactive Tab Bar — always positioned below the physical notch cutout!
            HStack(spacing: 6) {
                ForEach(IslandTab.allCases) { tab in
                    Button {
                        controller.selectedTab = tab
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.symbolName)
                                .font(.system(size: 11, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 11.5, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: true)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(controller.selectedTab == tab ? Color.white.opacity(0.20) : Color.white.opacity(0.05))
                        )
                        .foregroundColor(controller.selectedTab == tab ? .white : .white.opacity(0.72))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)

                if !hasHardwareNotch {
                    pinButton
                }
            }
            .padding(.top, hasHardwareNotch ? 2 : 6)

            Divider()
                .background(Color.white.opacity(0.12))

            // Active Tab Content
            Group {
                switch controller.selectedTab {
                case .clipboard:
                    ClipboardTabView(monitor: pasteboardMonitor)
                case .timer:
                    TimerTabView(adapter: keepAwakeAdapter)
                case .notes:
                    QuickNotesView(store: notesShelfStore)
                case .shelf:
                    FileShelfView(store: notesShelfStore)
                case .system:
                    SystemMetricsView(adapter: systemMetricsAdapter)
                case .home:
                    VStack(alignment: .leading, spacing: 8) {
                        MediaPlayerView(mediaAdapter: mediaAdapter)
                        Spacer(minLength: 0)
                        HStack {
                            Text(statusLine)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.55))
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 16)
        .padding(.top, hasHardwareNotch ? 4 : 10)
        .padding(.bottom, 12)
    }

    private var pinButton: some View {
        Button {
            controller.togglePin()
        } label: {
            Image(systemName: controller.viewState.mode == .pinned ? "pin.fill" : "pin")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(controller.viewState.mode == .pinned ? .yellow : .white.opacity(0.75))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(controller.viewState.mode == .pinned ? "Unpin Island" : "Pin Island")
    }

    private var statusLine: String {
        let displayType = hasHardwareNotch ? "Hardware Notch Safe Layout" : "Virtual Island"
        return "\(displayType) • Mode: \(String(describing: controller.viewState.mode))"
    }
}
