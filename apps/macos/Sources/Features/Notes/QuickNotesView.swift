import AppKit
import Combine
import Foundation
import IslandBridge
import IslandIntegrations
import SwiftUI

@MainActor
public final class NotesShelfStore: ObservableObject {
    @Published public private(set) var notes: [FfiNoteItem] = []
    @Published public private(set) var shelfItems: [FfiShelfItem] = []
    @Published public var selectedShelfItemIDs: Set<Int64> = []
    @Published public var draftTitle: String = ""
    @Published public var draftContent: String = ""

    private let core: IslandCore
    public let stagingManager: ShelfStagingManager

    public init(core: IslandCore, stagingManager: ShelfStagingManager = .shared) throws {
        self.core = core
        self.stagingManager = stagingManager
        try refresh()
    }

    public func refresh() throws {
        self.notes = try core.listNotes(limit: 30)
        self.shelfItems = try core.listShelfItems()
        let validIDs = Set(self.shelfItems.map(\.id))
        self.selectedShelfItemIDs = self.selectedShelfItemIDs.intersection(validIDs)
    }

    @discardableResult
    public func saveNote(
        noteId: Int64? = nil,
        title: String,
        content: String,
        nowSecs: Int64? = nil
    ) throws -> FfiNoteItem {
        let ts = nowSecs ?? Int64(Date().timeIntervalSince1970)
        let saved = try core.saveNote(noteId: noteId, title: title, content: content, nowSecs: ts)
        self.draftTitle = ""
        self.draftContent = ""
        try refresh()
        return saved
    }

    public func deleteNote(_ note: FfiNoteItem) throws {
        try core.deleteNote(noteId: note.id)
        try refresh()
    }

    @discardableResult
    public func addFileToShelf(url: URL, nowSecs: Int64? = nil) throws -> FfiShelfItem {
        let ts = nowSecs ?? Int64(Date().timeIntervalSince1970)
        let added = try core.addShelfItem(
            filePath: url.path,
            displayName: url.lastPathComponent,
            nowSecs: ts
        )
        try refresh()
        return added
    }

    @discardableResult
    public func addFilesToShelf(urls: [URL], nowSecs: Int64? = nil) throws -> [FfiShelfItem] {
        guard !urls.isEmpty else { return [] }
        let ts = nowSecs ?? Int64(Date().timeIntervalSince1970)
        var addedItems: [FfiShelfItem] = []
        for url in urls {
            let added = try core.addShelfItem(
                filePath: url.path,
                displayName: url.lastPathComponent,
                nowSecs: ts
            )
            addedItems.append(added)
        }
        try refresh()
        return addedItems
    }

    public func toggleShelfSelection(_ item: FfiShelfItem) {
        if selectedShelfItemIDs.contains(item.id) {
            selectedShelfItemIDs.remove(item.id)
        } else {
            selectedShelfItemIDs.insert(item.id)
        }
    }

    public func clearShelfSelection() {
        selectedShelfItemIDs.removeAll()
    }

    /// Returns file URLs for currently selected Shelf items, or all Shelf items if none are selected.
    public func selectedOrAllShelfURLs() -> [URL] {
        let targets = selectedShelfItemIDs.isEmpty
            ? shelfItems
            : shelfItems.filter { selectedShelfItemIDs.contains($0.id) }
        return targets.map { URL(fileURLWithPath: $0.filePath) }
    }

    public func removeShelfItem(_ item: FfiShelfItem) throws {
        try core.removeShelfItem(itemId: item.id)
        selectedShelfItemIDs.remove(item.id)
        stagingManager.cleanupStagedFileIfOwned(path: item.filePath)
        try refresh()
    }

    public func clearShelf() throws {
        try core.clearShelf()
        selectedShelfItemIDs.removeAll()
        stagingManager.cleanupAllStagedFiles()
        try refresh()
    }

    @discardableResult
    public func handleDroppedPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        ShelfDropResolver.resolveDrop(
            from: pasteboard,
            stagingManager: stagingManager
        ) { [weak self] urls in
            _ = try? self?.addFilesToShelf(urls: urls)
        }
    }
}

public struct QuickNotesView: View {
    @ObservedObject public var store: NotesShelfStore

    public init(store: NotesShelfStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Quick note...", text: Binding(
                    get: { store.draftContent },
                    set: { store.draftContent = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white)

                Button("Save") {
                    guard !store.draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    _ = try? store.saveNote(title: "Quick Note", content: store.draftContent)
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(store.notes, id: \.id) { note in
                        HStack {
                            Text(note.content)
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                                .lineLimit(2)
                            Spacer()
                            Button {
                                try? store.deleteNote(note)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundColor(.red.opacity(0.75))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                    }
                }
            }
        }
    }
}
