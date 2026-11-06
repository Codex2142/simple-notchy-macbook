import AppKit
import ApplicationServices
import Combine
import Foundation

/// Tracks feature-level macOS permissions on-demand without prompting at startup (PRD Section 8).
@MainActor
public final class PermissionManager: ObservableObject {
    @Published public private(set) var isAccessibilityGranted: Bool = false
    @Published public var isClipboardCaptureAuthorized: Bool

    public init(initialClipboardConsent: Bool = true) {
        self.isClipboardCaptureAuthorized = initialClipboardConsent
        refreshStatus()
    }

    /// Queries current macOS Accessibility status without showing a system prompt.
    public func refreshStatus() {
        self.isAccessibilityGranted = AXIsProcessTrusted()
    }

    /// Explicitly prompts the user for Accessibility access only when an Accessibility feature (e.g. Window Snapping) is invoked.
    public func requestAccessibilityOnDemand() -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        self.isAccessibilityGranted = trusted
        return trusted
    }
}
