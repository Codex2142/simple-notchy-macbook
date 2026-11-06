import SwiftUI
import IslandBridge
import IslandIntegrations

public struct ClipboardTabView: View {
    @ObservedObject public var monitor: PasteboardMonitor

    public init(monitor: PasteboardMonitor) {
        self.monitor = monitor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                TextField("Search clipboard history...", text: Binding(
                    get: { monitor.searchQuery },
                    set: { newValue in
                        monitor.searchQuery = newValue
                        try? monitor.refreshItems()
                    }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))

            if monitor.items.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("No clipboard items found")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(monitor.items, id: \.id) { item in
                            HStack(spacing: 8) {
                                // 1. Clipboard content region (scrollable)
                                Button {
                                    monitor.copyToPasteboard(item)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.textContent)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text(item.sourceApp)
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                // 2. Item action controls region (fixed width & accessible)
                                HStack(spacing: 8) {
                                    if monitor.copiedItemId == item.id {
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(.green)
                                            Text("Copied")
                                                .font(.system(size: 10.5, weight: .semibold))
                                                .foregroundColor(.green)
                                        }
                                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                                    } else {
                                        Button {
                                            monitor.copyToPasteboard(item)
                                        } label: {
                                            Image(systemName: "doc.on.doc")
                                                .font(.system(size: 11))
                                                .foregroundColor(.white.opacity(0.55))
                                        }
                                        .buttonStyle(.plain)
                                        .help("Copy to clipboard")
                                    }

                                    Button {
                                        try? monitor.togglePin(for: item)
                                    } label: {
                                        Image(systemName: item.isPinned ? "pin.fill" : "pin")
                                            .font(.system(size: 11))
                                            .foregroundColor(item.isPinned ? .yellow : .white.opacity(0.5))
                                    }
                                    .buttonStyle(.plain)
                                    .help(item.isPinned ? "Unpin item" : "Pin item")

                                    Button {
                                        try? monitor.deleteItem(item)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11))
                                            .foregroundColor(.red.opacity(0.75))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Delete item")
                                }
                                .fixedSize()
                            }
                            .padding(.leading, 8)
                            .padding(.trailing, 6)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                        }
                    }
                    // 3. Scrollbar region: Dedicated 14pt margin on trailing edge so vertical scrollbar never overlaps buttons
                    .padding(.trailing, 14)
                    .animation(.easeInOut(duration: 0.2), value: monitor.copiedItemId)
                }
            }
        }
    }
}
