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
    private var onboardingWindow: NSWindow?
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
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Snip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        if !permissions.isTrusted { openOnboarding() }
    }

    @objc private func openOnboarding() {
        if onboardingWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
                                  styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.title = "Welcome to Snip"
            window.contentView = NSHostingView(rootView: OnboardingView(
                isTrusted: { [weak self] in self?.permissions.isTrusted ?? false },
                requestTrust: { [weak self] in self?.permissions.requestTrust() },
                onGranted: { [weak self] in
                    self?.restartEventTap()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        self?.onboardingWindow?.close()
                    }
                }))
            window.isReleasedWhenClosed = false
            window.center()
            onboardingWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
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
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Snippets"
            // A dark, frosted HUD like the overlay: transparent titlebar, content edge to edge.
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.appearance = NSAppearance(named: .darkAqua)
            window.isOpaque = false
            window.backgroundColor = .clear
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
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                                  styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.title = "Snip Settings"
            window.contentView = NSHostingView(
                rootView: SettingsView(
                    model: model,
                    onConfigChanged: { [weak self] in self?.restartEventTap() },
                    onRecordingChange: { [weak self] recording in self?.engine?.setPaused(recording) }))
            window.isReleasedWhenClosed = false
            // Resume the tap if Settings is closed mid-recording, so a paused tap can't get stranded.
            window.delegate = self
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
            ignoredBundleIDs: model.ignoredBundleIDs,
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
        guard case let .wedge(index) = selection else { return }
        if let snippet = model.snippet(inSlot: index) {
            paster.insert(snippet)
        } else {
            // Empty wedge: create a snippet for that position and jump straight to editing it.
            let id = model.createSnippet(inSlot: index)
            openLibrary()
            // Hand off AFTER the window is key, next runloop tick, so the field focus actually lands.
            DispatchQueue.main.async { self.model.pendingEditSnippetID = id }
        }
    }

    @objc private func grantAccessibility() {
        permissions.requestTrust()
        restartEventTap()
    }

}

extension AppDelegate: NSWindowDelegate {
    /// Only the Settings window sets us as its delegate. If it closes mid-recording, the tap was left
    /// paused; resume it so the trigger keeps working. Resuming an already-live tap is a no-op.
    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow else { return }
        engine?.setPaused(false)
    }
}
