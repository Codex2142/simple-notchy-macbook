import AppKit
import Carbon.HIToolbox
import Combine
import Foundation
import IslandBridge

/// Monitors `NSPasteboard.general.changeCount` with minimal overhead, checking `IsSecureEventInputEnabled()`
/// and forwarding candidate items to `IslandCore` for privacy filtering and SQLite persistence.
@MainActor
public final class PasteboardMonitor: ObservableObject {
    @Published public private(set) var items: [FfiClipboardItem] = []
    @Published public var searchQuery: String = ""
    @Published public private(set) var copiedItemId: Int64?
    @Published public var showingDeleteAllConfirmation: Bool = false

    private let core: IslandCore
    private var lastChangeCount: Int
    private var pollTimer: Timer?
    private var copyFeedbackTask: Task<Void, Never>?
    public var isEnabled: Bool = true

    public init(core: IslandCore) throws {
        self.core = core
        self.lastChangeCount = NSPasteboard.general.changeCount
        self.items = try core.listClipboardItems(query: nil, limit: 50)
    }

    public func startMonitoring(interval: TimeInterval = 0.6) {
        stopMonitoring()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkPasteboardIfChanged()
            }
        }
    }

    public func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    public func checkPasteboardIfChanged() {
        guard isEnabled else { return }
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        guard let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let pbTypes = (pb.types ?? []).map(\.rawValue)
        let frontAppName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "macOS"
        let secureInput = IsSecureEventInputEnabled()

        _ = try? captureCandidate(
            text: text,
            sourceApp: frontAppName,
            pasteboardTypes: pbTypes,
            isSecureInputActive: secureInput
        )
    }

    /// Captures a candidate clipboard entry through Rust `IslandCore` and refreshes `items`.
    @discardableResult
    public func captureCandidate(
        text: String,
        sourceApp: String,
        pasteboardTypes: [String] = ["public.utf8-plain-text"],
        isSecureInputActive: Bool = false,
        nowSecs: Int64? = nil
    ) throws -> FfiClipboardItem {
        let timestamp = nowSecs ?? Int64(Date().timeIntervalSince1970)
        let item = try core.captureClipboardItem(
            input: FfiClipboardCaptureInput(
                contentType: "public.utf8-plain-text",
                textContent: text,
                sourceApp: sourceApp,
                pasteboardTypes: pasteboardTypes,
                isSecureInputActive: isSecureInputActive
            ),
            nowSecs: timestamp
        )
        try refreshItems()
        return item
    }

    public func refreshItems() throws {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        self.items = try core.listClipboardItems(
            query: query.isEmpty ? nil : query,
            limit: 50
        )
    }

    public func togglePin(for item: FfiClipboardItem) throws {
        try core.setClipboardItemPinned(itemId: item.id, pinned: !item.isPinned)
        try refreshItems()
    }

    public func deleteItem(_ item: FfiClipboardItem) throws {
        try core.deleteClipboardItem(itemId: item.id)
        try refreshItems()
    }

    @discardableResult
    public func clearAllHistory() -> Bool {
        do {
            _ = try core.clearClipboardHistory()
            try refreshItems()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public func copyToPasteboard(_ item: FfiClipboardItem) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        let success = pb.setString(item.textContent, forType: .string)
        if success {
            lastChangeCount = pb.changeCount
            copyFeedbackTask?.cancel()
            copiedItemId = item.id
            copyFeedbackTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled, let self else { return }
                if self.copiedItemId == item.id {
                    self.copiedItemId = nil
                }
            }
        }
        return success
    }
}
