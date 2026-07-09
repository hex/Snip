// ABOUTME: Owns the Accessibility (AX) trust check that gates the event tap and synthetic input.
// ABOUTME: Without trust, CGEvent.tapCreate returns nil and CGEvent.post silently no-ops.
import ApplicationServices

final class PermissionsCoordinator {
    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Prompts once (ever) and opens System Settings on first denial.
    func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
