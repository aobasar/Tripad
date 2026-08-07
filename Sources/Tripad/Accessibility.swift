import AppKit
import ApplicationServices

/// Thin wrapper over the Accessibility trust check. A `CGEventTap` on gesture
/// events cannot be created without this permission, so the app checks it
/// before installing the tap and keeps checking until it is granted.
enum Accessibility {

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Triggers the system prompt that offers to open Privacy & Security.
    /// Only shown once per app identity; afterwards it is a silent no-op,
    /// which is why `openSettings()` exists as the manual fallback.
    static func requestPrompt() {
        // Spelled out rather than using kAXTrustedCheckOptionPrompt: the
        // imported constant is a mutable global and trips strict concurrency.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
