import AppKit
import SwiftUI
import UniformTypeIdentifiers
import IslandBridge

public struct FileShelfView: View {
    @ObservedObject public var store: NotesShelfStore

    public init(store: NotesShelfStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Drop files here for temporary holding or AirDrop", systemImage: "tray.and.arrow.down.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
                if !store.shelfItems.isEmpty {
                    Button("Clear") {
                        try? store.clearShelf()
                    }
                    .font(.system(size: 10))
                }
            }

            if store.shelfItems.isEmpty {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                    .foregroundColor(.white.opacity(0.25))
                    .overlay(
                        Text("Drag files to the Notch to add to Shelf")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.shelfItems, id: \.id) { item in
                            HStack(spacing: 6) {
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.cyan)
                                Text(item.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Button {
                                    let url = URL(fileURLWithPath: item.filePath)
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                } label: {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.65))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    try? store.removeShelfItem(item)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                            .onDrag {
                                NSItemProvider(object: URL(fileURLWithPath: item.filePath) as NSURL)
                            }
                        }
                    }
                }
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        _ = try? store.addFileToShelf(url: url)
                    }
                }
            }
            return true
        }
    }
}
