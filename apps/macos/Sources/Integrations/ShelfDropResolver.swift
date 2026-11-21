import AppKit
import Foundation
import UniformTypeIdentifiers

/// Resolves macOS drag-and-drop `NSPasteboard` payloads into local file URLs for the File Shelf.
/// Supports:
/// 1. Local files & folders from Finder, VS Code (Electron), IDEs, and Terminal
///    (`public.file-url` as URL or raw UTF-8 `Data`, `NSFilenamesPboardType`, `file://` URLs, existing local path strings)
/// 2. `NSFilePromiseReceiver` (Photos, Mail, macOS Screenshot preview, Safari/Chrome promises)
/// 3. Raw image data (`png`, `jpeg`, `heic`, `webp`, `tiff`, `public.image`)
/// 4. Browser remote `<img>` URLs (downloaded & validated as image data)
/// Explicitly rejects non-file plain text and non-image web URLs.
public enum ShelfDropResolver {
    public static let fileNamesPboardType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    public static let uriListPboardType = NSPasteboard.PasteboardType("public.uri-list")
    public static let jpegPboardType = NSPasteboard.PasteboardType(UTType.jpeg.identifier)
    public static let heicPboardType = NSPasteboard.PasteboardType("public.heic")
    public static let webpPboardType = NSPasteboard.PasteboardType("org.webmproject.webp")
    public static let genericImagePboardType = NSPasteboard.PasteboardType(UTType.image.identifier)

    private static let recognizedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "tif", "bmp", "avif"
    ]

    private static let rawImageTypePriority: [(type: NSPasteboard.PasteboardType, ext: String)] = [
        (.png, "png"),
        (jpegPboardType, "jpg"),
        (heicPboardType, "heic"),
        (webpPboardType, "webp"),
        (.tiff, "tiff"),
        (genericImagePboardType, "png"),
    ]

    private static let filePromiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.projectisland.shelf.filepromises"
        queue.qualityOfService = .userInitiated
        return queue
    }()

    /// All pasteboard types that `IslandHostingView` should register for drag-and-drop.
    public static var supportedPasteboardTypes: [NSPasteboard.PasteboardType] {
        var types = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        types.append(contentsOf: [
            .fileURL,
            fileNamesPboardType,
            uriListPboardType,
            .URL,
            .html,
            .string,
            .png,
            jpegPboardType,
            heicPboardType,
            webpPboardType,
            .tiff,
            genericImagePboardType,
        ])
        return types
    }

    /// Fast synchronous validation used during `draggingEntered` / `draggingUpdated`.
    public static func canAccept(pasteboard: NSPasteboard) -> Bool {
        if !extractLocalFileURLs(from: pasteboard).isEmpty {
            return true
        }
        if hasFilePromises(in: pasteboard) {
            return true
        }
        if hasRawImageData(in: pasteboard) {
            return true
        }
        if !extractRemoteImageURLs(from: pasteboard).isEmpty {
            return true
        }
        return false
    }

    /// Extracts and materializes supported File & Media items from `pasteboard`.
    /// Supports multi-file drags and mixed batches (e.g., local files + raw images/promises)
    /// while deduplicating multi-representation single items.
    @discardableResult
    public static func resolveDrop(
        from pasteboard: NSPasteboard,
        stagingManager: ShelfStagingManager,
        onResolvedURLs: @escaping @MainActor @Sendable ([URL]) -> Void
    ) -> Bool {
        var handledAny = false

        // 1. Local files / folders (Finder, VS Code, Cursor, Xcode, JetBrains, Terminal)
        let localURLs = extractLocalFileURLs(from: pasteboard)
        if !localURLs.isEmpty {
            handledAny = true
            Task { @MainActor in
                onResolvedURLs(localURLs)
            }
        }

        // 2. File Promises (Photos, Mail, Screenshot preview, Safari/Chrome)
        // Skip promises only if local file URLs already covered every pasteboard item
        // (prevents duplicating apps that attach both a local fileURL and a promise for the same item).
        let pasteboardItemCount = pasteboard.pasteboardItems?.count ?? 0
        if localURLs.count < max(1, pasteboardItemCount),
           let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
           !receivers.isEmpty
        {
            if (try? stagingManager.ensureDirectoryExists()) != nil {
                handledAny = true
                for receiver in receivers {
                    receiver.receivePromisedFiles(
                        atDestination: stagingManager.stagingDirectory,
                        options: [:],
                        operationQueue: filePromiseQueue
                    ) { fileURL, error in
                        guard error == nil else { return }
                        Task { @MainActor in
                            onResolvedURLs([fileURL])
                        }
                    }
                }
            }
        }

        // 3. Raw image data for items that did not already resolve to a local file URL
        let rawImages = extractRawImagePayloads(from: pasteboard, excludingItemsWithLocalFiles: !localURLs.isEmpty)
        if !rawImages.isEmpty {
            var stagedURLs: [URL] = []
            for payload in rawImages {
                if let stagedURL = try? stagingManager.stageImageData(
                    payload.data,
                    preferredExtension: payload.ext,
                    suggestedName: payload.suggestedName
                ) {
                    stagedURLs.append(stagedURL)
                }
            }
            if !stagedURLs.isEmpty {
                handledAny = true
                let batch = stagedURLs
                Task { @MainActor in
                    onResolvedURLs(batch)
                }
            }
        }

        // 4. Remote image URLs from browser drag (only when not already handled by promises/raw images)
        if !handledAny {
            let remoteImageURLs = extractRemoteImageURLs(from: pasteboard)
            if !remoteImageURLs.isEmpty {
                handledAny = true
                for remoteURL in remoteImageURLs {
                    Task.detached(priority: .userInitiated) {
                        guard let stagedURL = await downloadAndStageImage(from: remoteURL, stagingManager: stagingManager) else {
                            return
                        }
                        await MainActor.run {
                            onResolvedURLs([stagedURL])
                        }
                    }
                }
            }
        }

        return handledAny
    }

    /// Backwards-compatible single-URL callback overload.
    @discardableResult
    public static func resolveDrop(
        from pasteboard: NSPasteboard,
        stagingManager: ShelfStagingManager,
        onResolvedURL: @escaping @MainActor @Sendable (URL) -> Void
    ) -> Bool {
        resolveDrop(from: pasteboard, stagingManager: stagingManager) { urls in
            for url in urls {
                onResolvedURL(url)
            }
        }
    }

    // MARK: - Local File Extraction (Finder, VS Code / Electron, IDEs)

    public static func extractLocalFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        var collected: [URL] = []
        var seenPaths = Set<String>()

        func appendIfValid(_ url: URL) {
            guard url.isFileURL else { return }
            let standardized = url.standardizedFileURL
            let path = standardized.path
            guard !path.isEmpty, !seenPaths.contains(path) else { return }
            seenPaths.insert(path)
            collected.append(standardized)
        }

        func appendFromMultilineText(_ raw: String) {
            let lines = raw
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            for line in lines {
                if let url = parseFileURLOrExistingPath(line) {
                    appendIfValid(url)
                }
            }
        }

        // 1. Legacy NSFilenamesPboardType (widely used by Electron/VS Code & Finder multi-file drags)
        if let paths = pasteboard.propertyList(forType: fileNamesPboardType) as? [String] {
            for path in paths where !path.isEmpty {
                appendIfValid(URL(fileURLWithPath: path))
            }
        }

        // 2. Standard AppKit NSURL reading
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            for url in urls {
                appendIfValid(url)
            }
        }

        // 3. Per-item inspection (handles VS Code / Electron raw UTF-8 `Data` for `public.file-url`,
        //    multi-line `text/uri-list`, and multi-file path lists in `public.utf8-plain-text`).
        //    Always inspects all representations per item because deduplication prevents duplicates
        //    while capturing all files when an app puts 1 file in `.fileURL` and N paths in `.string`.
        for item in pasteboard.pasteboardItems ?? [] {
            for url in localFileURLs(in: item, parseMultiline: appendFromMultilineText) {
                appendIfValid(url)
            }
        }

        return collected
    }

    private static func itemHasLocalFile(_ item: NSPasteboardItem) -> Bool {
        var found = false
        let direct = localFileURLs(in: item) { raw in
            let lines = raw
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            for line in lines where parseFileURLOrExistingPath(line) != nil {
                found = true
                break
            }
        }
        return found || !direct.isEmpty
    }

    private static func localFileURLs(
        in item: NSPasteboardItem,
        parseMultiline: (String) -> Void
    ) -> [URL] {
        var results: [URL] = []

        if let data = item.data(forType: .fileURL) {
            if let str = String(data: data, encoding: .utf8),
               str.contains("\n") || str.contains("\r")
            {
                parseMultiline(str)
            } else if let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
                results.append(url)
            } else if let str = String(data: data, encoding: .utf8) {
                parseMultiline(str)
            }
        }

        if let str = item.string(forType: .fileURL) {
            parseMultiline(str)
        }

        if let str = item.string(forType: uriListPboardType) {
            parseMultiline(str)
        } else if let data = item.data(forType: uriListPboardType),
                  let str = String(data: data, encoding: .utf8)
        {
            parseMultiline(str)
        }

        if let str = item.string(forType: .URL),
           let url = URL(string: str.trimmingCharacters(in: .whitespacesAndNewlines)),
           url.isFileURL
        {
            results.append(url)
        }

        if let rawString = item.string(forType: .string) {
            parseMultiline(rawString)
        }

        return results
    }

    private static func parseFileURLOrExistingPath(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("file://") {
            if let url = URL(string: trimmed), url.isFileURL {
                return url
            }
            if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
               let url = URL(string: encoded), url.isFileURL
            {
                return url
            }
        }

        let expanded: String
        if trimmed.hasPrefix("~/") {
            expanded = (trimmed as NSString).expandingTildeInPath
        } else if trimmed.hasPrefix("/") {
            expanded = trimmed
        } else {
            return nil
        }

        guard FileManager.default.fileExists(atPath: expanded) else { return nil }
        return URL(fileURLWithPath: expanded)
    }

    // MARK: - File Promises & Raw Image Inspection

    private static func hasFilePromises(in pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil)
    }

    private static func hasRawImageData(in pasteboard: NSPasteboard) -> Bool {
        let availableTypes = Set(pasteboard.types ?? [])
        return rawImageTypePriority.contains { availableTypes.contains($0.type) }
    }

    private struct RawImagePayload {
        let data: Data
        let ext: String
        let suggestedName: String?
    }

    private static func extractRawImagePayloads(
        from pasteboard: NSPasteboard,
        excludingItemsWithLocalFiles: Bool = false
    ) -> [RawImagePayload] {
        var payloads: [RawImagePayload] = []

        for item in pasteboard.pasteboardItems ?? [] {
            if excludingItemsWithLocalFiles && itemHasLocalFile(item) {
                continue
            }
            for candidate in rawImageTypePriority {
                if let data = item.data(forType: candidate.type), !data.isEmpty {
                    let suggested = suggestedImageName(from: item)
                    payloads.append(RawImagePayload(data: data, ext: candidate.ext, suggestedName: suggested))
                    break
                }
            }
        }

        if payloads.isEmpty && !excludingItemsWithLocalFiles {
            for candidate in rawImageTypePriority {
                if let data = pasteboard.data(forType: candidate.type), !data.isEmpty {
                    payloads.append(RawImagePayload(data: data, ext: candidate.ext, suggestedName: nil))
                    break
                }
            }
        }

        return payloads
    }

    private static func suggestedImageName(from item: NSPasteboardItem) -> String? {
        if let urlStr = item.string(forType: .URL),
           let url = URL(string: urlStr.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            let name = url.deletingPathExtension().lastPathComponent
            if !name.isEmpty, name != "/" {
                return name
            }
        }
        return nil
    }

    // MARK: - Browser Remote Image URL Extraction & Download

    public static func extractRemoteImageURLs(from pasteboard: NSPasteboard) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()

        func appendIfRemote(_ url: URL) {
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
            let key = url.absoluteString
            guard !seen.contains(key) else { return }
            seen.insert(key)
            urls.append(url)
        }

        for item in pasteboard.pasteboardItems ?? [] {
            // 1. HTML `<img src="https://...">` emitted by Chrome/Safari/Arc on image drags
            if let html = item.string(forType: .html) {
                for src in extractImgSrcURLs(fromHTML: html) {
                    appendIfRemote(src)
                }
            }

            // 2. Direct remote image URL with recognized image extension
            if let urlStr = item.string(forType: .URL),
               let url = URL(string: urlStr.trimmingCharacters(in: .whitespacesAndNewlines)),
               isLikelyImageURL(url)
            {
                appendIfRemote(url)
            }
        }

        return urls
    }

    private static func isLikelyImageURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return recognizedImageExtensions.contains(ext)
    }

    private static func extractImgSrcURLs(fromHTML html: String) -> [URL] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: nsRange)
        return matches.compactMap { match -> URL? in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: html)
            else {
                return nil
            }
            let rawSrc = String(html[range])
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return URL(string: rawSrc)
        }
    }

    private static func downloadAndStageImage(
        from remoteURL: URL,
        stagingManager: ShelfStagingManager
    ) async -> URL? {
        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 10.0

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              !data.isEmpty
        else {
            return nil
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode)
        {
            return nil
        }

        let mimeType = (response.mimeType ?? "").lowercased()
        let isMimeImage = mimeType.hasPrefix("image/")
        let isDecodableImage = NSImage(data: data) != nil
        guard isMimeImage || isDecodableImage else {
            return nil
        }

        let ext = resolveImageExtension(mimeType: mimeType, url: remoteURL)
        let suggestedName = remoteURL.deletingPathExtension().lastPathComponent
        return try? stagingManager.stageImageData(
            data,
            preferredExtension: ext,
            suggestedName: suggestedName.isEmpty ? "WebImage" : suggestedName
        )
    }

    private static func resolveImageExtension(mimeType: String, url: URL) -> String {
        switch mimeType {
        case "image/png": return "png"
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/heic": return "heic"
        case "image/tiff": return "tiff"
        case "image/bmp": return "bmp"
        default:
            let urlExt = url.pathExtension.lowercased()
            return recognizedImageExtensions.contains(urlExt) ? urlExt : "png"
        }
    }
}
