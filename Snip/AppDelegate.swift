// ABOUTME: App lifecycle owner: creates the menu-bar status item and (for now) smoke-test actions.
// ABOUTME: Later wires the event tap, overlay, paste engine, and windows.
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let permissions = PermissionsCoordinator()
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        seedSampleSnippetsIfEmpty()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // "Snip" is short for Snippets: the app inserts text, it never cuts. Hence text.insert.
        // A misspelled symbol name yields nil, which would leave an invisible status item.
        if let icon = NSImage(systemSymbolName: "text.insert", accessibilityDescription: "Snip") {
            statusItem.button?.image = icon
        } else {
            statusItem.button?.title = "Snip"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Grant Accessibility…", action: #selector(grantAccessibility), keyEquivalent: "")
        menu.addItem(withTitle: "Smoke: paste \"hello\"", action: #selector(smokePaste), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Snip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    /// Gives a fresh install something on the ring so the radial is testable immediately.
    private func seedSampleSnippetsIfEmpty() {
        guard model.library.snippets.isEmpty else { return }
        model.library.snippets = [
            .init(label: "SIG", body: "Best,\nAlex", slot: 0),
            .init(label: "DATE", body: "{date}", slot: 1),
            .init(label: "HI", body: "Hi $|,\n\nThanks,\nAlex", slot: 5),
        ]
        model.save()
    }

    @objc private func grantAccessibility() {
        permissions.requestTrust()
    }

    @objc private func smokePaste() {
        guard permissions.isTrusted else { NSSound.beep(); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("hello", forType: .string)
        let src = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)   // 'v'
        let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
    }
}
