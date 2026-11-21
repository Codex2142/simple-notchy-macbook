import AppKit
import ImageIO
import IslandBridge
import SwiftUI

public struct FileShelfView: View {
    @ObservedObject public var store: NotesShelfStore
    public var isDragTargeted: Bool

    public init(store: NotesShelfStore, isDragTargeted: Bool = false) {
        self.store = store
        self.isDragTargeted = isDragTargeted
    }

    private var dragOutURLs: [URL] {
        store.selectedOrAllShelfURLs()
    }

    private var dragOutLabel: String {
        if !store.selectedShelfItemIDs.isEmpty {
            return "Drag Selected (\(store.selectedShelfItemIDs.count))"
        }
        return "Drag All (\(store.shelfItems.count))"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(
                    isDragTargeted
                        ? "Release to add to Shelf"
                        : "Drop files or images here for temporary holding or AirDrop",
                    systemImage: isDragTargeted ? "arrow.down.doc.fill" : "tray.and.arrow.down.fill"
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isDragTargeted ? .cyan : .white.opacity(0.75))
                .lineLimit(1)
                Spacer(minLength: 4)
                if !store.shelfItems.isEmpty {
                    MultiFileDragHandleView(
                        urls: dragOutURLs,
                        title: dragOutLabel
                    )
                    .fixedSize()

                    if !store.selectedShelfItemIDs.isEmpty {
                        Button("Deselect") {
                            store.clearShelfSelection()
                        }
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                        .buttonStyle(.plain)
                    }

                    Button("Clear") {
                        try? store.clearShelf()
                    }
                    .font(.system(size: 10))
                }
            }

            if store.shelfItems.isEmpty {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isDragTargeted ? Color.cyan.opacity(0.12) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                style: StrokeStyle(lineWidth: isDragTargeted ? 1.5 : 1, dash: [5])
                            )
                            .foregroundColor(isDragTargeted ? .cyan : .white.opacity(0.25))
                    )
                    .overlay(
                        Text(isDragTargeted ? "Drop to add to Shelf" : "Drag files or images to the Notch to add to Shelf")
                            .font(.system(size: 11, weight: isDragTargeted ? .semibold : .regular))
                            .foregroundColor(isDragTargeted ? .cyan : .white.opacity(0.5))
                    )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.shelfItems, id: \.id) { item in
                            let isSelected = store.selectedShelfItemIDs.contains(item.id)
                            HStack(spacing: 6) {
                                ShelfItemIconView(filePath: item.filePath)
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
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? Color.cyan.opacity(0.22) : Color.white.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(
                                        isSelected ? Color.cyan : Color.clear,
                                        lineWidth: 1.2
                                    )
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture {
                                store.toggleShelfSelection(item)
                            }
                            .onDrag {
                                NSItemProvider(object: URL(fileURLWithPath: item.filePath) as NSURL)
                            }
                        }
                    }
                }
                .padding(isDragTargeted ? 4 : 0)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isDragTargeted ? Color.cyan.opacity(0.10) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isDragTargeted ? Color.cyan : Color.clear,
                            style: StrokeStyle(lineWidth: 1.5, dash: [5])
                        )
                )
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isDragTargeted)
    }
}

/// AppKit-backed drag handle that initiates a native multi-file `NSDraggingSession`
/// so multiple Shelf items can be dragged out simultaneously into Finder, VS Code, Slack, Mail, or AirDrop.
private struct MultiFileDragHandleView: NSViewRepresentable {
    let urls: [URL]
    let title: String

    func makeNSView(context: Context) -> MultiFileDragHandleNSView {
        let view = MultiFileDragHandleNSView()
        view.urls = urls
        view.title = title
        return view
    }

    func updateNSView(_ nsView: MultiFileDragHandleNSView, context: Context) {
        nsView.urls = urls
        nsView.title = title
    }
}

private final class MultiFileDragHandleNSView: NSView, NSDraggingSource {
    var urls: [URL] = []
    var title: String = "" {
        didSet {
            label.stringValue = title
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    private let iconView: NSImageView = {
        let iv = NSImageView()
        iv.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "Drag multiple items")
        iv.contentTintColor = .systemCyan
        iv.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let label: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.font = .systemFont(ofSize: 10, weight: .semibold)
        tf.textColor = .systemCyan
        tf.lineBreakMode = .byTruncatingTail
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    private var mouseDownPoint: NSPoint?
    private var didStartDrag: Bool = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.systemCyan.withAlphaComponent(0.16).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.systemCyan.withAlphaComponent(0.45).cgColor

        addSubview(iconView)
        addSubview(label)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let labelSize = label.intrinsicContentSize
        return NSSize(width: labelSize.width + 26, height: 20)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag, !urls.isEmpty, let start = mouseDownPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        let distance = hypot(current.x - start.x, current.y - start.y)
        guard distance >= 3.0 else { return }

        didStartDrag = true
        let draggingItems: [NSDraggingItem] = urls.enumerated().map { idx, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32)
            let offset = CGFloat(min(idx, 4)) * 3.0
            let frame = NSRect(x: current.x - 16 + offset, y: current.y - 16 - offset, width: 32, height: 32)
            item.setDraggingFrame(frame, contents: icon)
            return item
        }
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
        didStartDrag = false
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }
}

/// Renders a cached downsampled thumbnail preview for image files, or the native macOS file/folder icon otherwise.
private struct ShelfItemIconView: View {
    let filePath: String

    private static let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        return cache
    }()

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "tif", "bmp", "avif"
    ]

    private var isImageFile: Bool {
        let ext = URL(fileURLWithPath: filePath).pathExtension.lowercased()
        return Self.imageExtensions.contains(ext)
    }

    var body: some View {
        if isImageFile, let thumbnail = Self.cachedThumbnail(forPath: filePath) {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: filePath))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
        }
    }

    private static func cachedThumbnail(forPath path: String) -> NSImage? {
        let key = path as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }
        guard let loaded = loadDownsampledThumbnail(atPath: path, maxPixelSize: 48) else {
            return nil
        }
        thumbnailCache.setObject(loaded, forKey: key)
        return loaded
    }

    private static func loadDownsampledThumbnail(atPath path: String, maxPixelSize: Int) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
