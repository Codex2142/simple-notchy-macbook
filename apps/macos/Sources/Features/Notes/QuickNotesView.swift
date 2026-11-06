import Combine
import Foundation
import IslandBridge
import SwiftUI

@MainActor
public final class NotesShelfStore: ObservableObject {
    @Published public private(set) var notes: [FfiNoteItem] = []
    @Published public private(set) var shelfItems: [FfiShelfItem] = []
    @Published public var draftTitle: String = ""
    @Published public var draftContent: String = ""

    private let core: IslandCore

    public init(core: IslandCore) throws {
        self.core = core
        try refresh()
    }

    public func refresh() throws {
        self.notes = try core.listNotes(limit: 30)
        self.shelfItems = try core.listShelfItems()
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

    public func removeShelfItem(_ item: FfiShelfItem) throws {
        try core.removeShelfItem(itemId: item.id)
        try refresh()
    }

    public func clearShelf() throws {
        try core.clearShelf()
        try refresh()
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
