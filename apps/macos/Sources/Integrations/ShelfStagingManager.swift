import AppKit
import Foundation

/// Manages internal staging storage for non-path media dropped onto the Shelf
/// (e.g., `NSFilePromiseReceiver` payloads from Photos/Mail/Screenshots and browser/raw images).
/// Guarantees that cleanup operations only delete files strictly inside the staging directory.
public final class ShelfStagingManager: Sendable {
    public static let shared = ShelfStagingManager()

    public let stagingDirectory: URL

    public init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.stagingDirectory = baseDirectory.standardizedFileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.stagingDirectory = appSupport
                .appendingPathComponent("ProjectIsland", isDirectory: true)
                .appendingPathComponent("ShelfStaging", isDirectory: true)
                .standardizedFileURL
        }
    }

    public func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
    }

    /// Generates a unique, sanitized destination file URL inside `stagingDirectory`.
    public func makeDestinationURL(suggestedName: String?, fileExtension: String) throws -> URL {
        try ensureDirectoryExists()
        let cleanExt = fileExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            .lowercased()
        let resolvedExt = cleanExt.isEmpty ? "png" : cleanExt

        let rawBase = (suggestedName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let strippedName = URL(fileURLWithPath: rawBase).deletingPathExtension().lastPathComponent
        let sanitizedBase = Self.sanitizeFilename(strippedName.isEmpty ? "Image" : strippedName)

        let shortID = String(UUID().uuidString.prefix(8)).lowercased()
        let filename = "\(shortID)_\(sanitizedBase).\(resolvedExt)"
        return stagingDirectory.appendingPathComponent(filename, isDirectory: false)
    }

    /// Stages raw image bytes to disk. Converts TIFF payloads to PNG when possible
    /// for smaller footprint and broad drag-out compatibility.
    public func stageImageData(
        _ data: Data,
        preferredExtension: String,
        suggestedName: String? = nil
    ) throws -> URL {
        let lowerExt = preferredExtension.lowercased()
        if (lowerExt == "tiff" || lowerExt == "tif"),
           let bitmap = NSBitmapImageRep(data: data),
           let pngData = bitmap.representation(using: .png, properties: [:])
        {
            let destURL = try makeDestinationURL(suggestedName: suggestedName, fileExtension: "png")
            try pngData.write(to: destURL, options: .atomic)
            return destURL
        }

        let destURL = try makeDestinationURL(suggestedName: suggestedName, fileExtension: lowerExt)
        try data.write(to: destURL, options: .atomic)
        return destURL
    }

    /// Returns true if and only if `path` resides strictly inside `stagingDirectory`.
    public func isStagedFile(path: String) -> Bool {
        let standardizedTarget = URL(fileURLWithPath: path).standardizedFileURL.path
        let standardizedRoot = stagingDirectory.standardizedFileURL.path
        let prefix = standardizedRoot.hasSuffix("/") ? standardizedRoot : standardizedRoot + "/"
        return standardizedTarget.hasPrefix(prefix)
    }

    /// Deletes a staged file if it belongs to `stagingDirectory`. Never touches user files outside staging.
    public func cleanupStagedFileIfOwned(path: String) {
        guard isStagedFile(path: path) else { return }
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    /// Removes all staged files inside `stagingDirectory`.
    public func cleanupAllStagedFiles() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: stagingDirectory.path),
              let contents = try? fm.contentsOfDirectory(at: stagingDirectory, includingPropertiesForKeys: nil)
        else {
            return
        }
        for url in contents where isStagedFile(path: url.path) {
            try? fm.removeItem(at: url)
        }
    }

    private static func sanitizeFilename(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let filtered = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let collapsed = String(filtered)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
        if collapsed.isEmpty {
            return "Image"
        }
        return String(collapsed.prefix(48))
    }
}
