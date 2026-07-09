// ABOUTME: App lifecycle owner: creates the menu-bar status item and (for now) smoke-test actions.
// ABOUTME: Later wires the event tap, overlay, paste engine, and windows.
import AppKit
import SwiftUI
import SnipKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let permissions = PermissionsCoordinator()
    private var overlay: OverlayPanelController!
    private var engine: EventTapEngine!
    private let paster = PasteEngine()
    private var libraryWindow: NSWindow?
    private var settingsWindow: NSWindow?
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        seedSampleSnippetsIfEmpty()
        overlay = OverlayPanelController(model: model)   // prewarms the panel + SwiftUI graph
        startEventTap()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // "Snip" is short for Snippets: the app inserts text, it never cuts. Hence text.insert.
        // A misspelled symbol name yields nil, which would leave an invisible status item.
        if let icon = NSImage(systemSymbolName: "text.insert", accessibilityDescription: "Snip") {
            statusItem.button?.image = icon
        } else {
            statusItem.button?.title = "Snip"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Snippets…", action: #selector(openLibrary), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Grant Accessibility…", action: #selector(grantAccessibility), keyEquivalent: "")
        menu.addItem(withTitle: "Smoke: paste \"hello\"", action: #selector(smokePaste), keyEquivalent: "")
        menu.addItem(withTitle: "Debug: bloom ring in 3s", action: #selector(debugBloom), keyEquivalent: "")
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

    @objc private func openLibrary() {
        if libraryWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Snip Snippets"
            window.contentView = NSHostingView(rootView: LibraryView(model: model))
            window.isReleasedWhenClosed = false
            window.center()
            libraryWindow = window
        }
        // Unlike the overlay, this window is meant to take focus.
        NSApp.activate(ignoringOtherApps: true)
        libraryWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 260),
                                  styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.title = "Snip Settings"
            window.contentView = NSHostingView(
                rootView: SettingsView(model: model, onConfigChanged: { [weak self] in
                    self?.restartEventTap()
                }))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// The tap's event mask and trigger rules are fixed at creation, so a config change rebuilds it.
    private func restartEventTap() {
        engine?.stop()
        startEventTap()
    }

    private func startEventTap() {
        engine = EventTapEngine(
            config: model.triggerConfig,
            permissions: permissions,
            onBloom: { [weak self] anchor in self?.overlay.show(atQuartz: anchor) },
            onPointer: { [weak self] selection in self?.overlay.update(selection: selection) },
            onCommit: { [weak self] selection in
                self?.overlay.hide()
                self?.fire(selection)
            },
            onCancel: { [weak self] in self?.overlay.hide() })

        if !engine.start() { permissions.requestTrust() }
    }

    private func fire(_ selection: RadialSelection) {
        guard case let .wedge(index) = selection, let snippet = model.snippet(inSlot: index) else { return }
        paster.insert(snippet)
    }

    @objc private func grantAccessibility() {
        permissions.requestTrust()
        restartEventTap()
    }

    /// Blooms after a delay so the tester can hand focus to another app first —
    /// proving the panel appears without activating Snip.
    @objc private func debugBloom() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let mouse = NSEvent.mouseLocation
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            self.overlay.show(atQuartz: CGPoint(x: mouse.x, y: primaryHeight - mouse.y))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.overlay.update(selection: .wedge(5))   // "HI" slot
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                self.overlay.hide()
            }
        }
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
