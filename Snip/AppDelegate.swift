// ABOUTME: App lifecycle owner: creates the menu-bar status item and (for now) smoke-test actions.
// ABOUTME: Later wires the event tap, overlay, paste engine, and windows.
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let permissions = PermissionsCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
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
