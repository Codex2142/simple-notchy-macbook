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

                                Button {
                                    try? monitor.togglePin(for: item)
                                } label: {
                                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                                        .font(.system(size: 11))
                                        .foregroundColor(item.isPinned ? .yellow : .white.opacity(0.5))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    try? monitor.deleteItem(item)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundColor(.red.opacity(0.75))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                        }
                    }
                }
            }
        }
    }
}
