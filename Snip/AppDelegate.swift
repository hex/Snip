// ABOUTME: App lifecycle owner: creates the menu-bar status item and (for now) smoke-test actions.
// ABOUTME: Later wires the event tap, overlay, paste engine, and windows.
import AppKit
import SwiftUI
import SnipKit

/// The menu-bar mark: a minimal monochrome echo of the app's segmented dial — a stroked outer ring,
/// eight wedge spokes, and a hub dot. A template image, so the menu bar tints it for light and dark and
/// for selection the way a system status item does.
func menuBarDialImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer: CGFloat = 8
        let inner: CGFloat = 3.6
        NSColor.black.set()

        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - outer, y: center.y - outer,
                                               width: outer * 2, height: outer * 2))
        ring.lineWidth = 1.2
        ring.stroke()

        // Wedge boundaries: eight spokes, offset 22.5° from vertical so the top is a wedge center (the
        // lit slot), matching the ring in the app.
        let spokes = NSBezierPath()
        spokes.lineWidth = 0.9
        for step in 0..<8 {
            let angle = Double.pi / 8 + Double(step) * (Double.pi / 4)
            let dx = CGFloat(cos(angle)), dy = CGFloat(sin(angle))
            spokes.move(to: CGPoint(x: center.x + dx * inner, y: center.y + dy * inner))
            spokes.line(to: CGPoint(x: center.x + dx * outer, y: center.y + dy * outer))
        }
        spokes.stroke()

        let hub: CGFloat = 1.7
        NSBezierPath(ovalIn: NSRect(x: center.x - hub, y: center.y - hub,
                                    width: hub * 2, height: hub * 2)).fill()
        return true
    }
    image.isTemplate = true
    return image
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let permissions = PermissionsCoordinator()
    private var overlay: OverlayPanelController!
    private var engine: EventTapEngine!
    private let paster = PasteEngine()
    private var mainWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var grantItem: NSMenuItem?
    private var grantSeparator: NSMenuItem?
    private var updater: UpdaterController!
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        updater = UpdaterController()
        seedSampleSnippetsIfEmpty()
        installMainMenu()
        overlay = OverlayPanelController(model: model)   // prewarms the panel + SwiftUI graph
        startEventTap()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = menuBarDialImage()
        statusItem.button?.image?.accessibilityDescription = "Snip"

        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        // Accessibility is a one-time grant; menuNeedsUpdate hides this and its divider once trusted.
        grantItem = menu.addItem(withTitle: "Grant Accessibility…", action: #selector(grantAccessibility), keyEquivalent: "")
        let grantDivider = NSMenuItem.separator()
        grantSeparator = grantDivider
        menu.addItem(grantDivider)
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Snip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu

        if !permissions.isTrusted { openOnboarding() }
    }

    /// A menu-bar agent shows no menu bar, but key equivalents still route through NSApp.mainMenu.
    /// Without an Edit menu, Cmd+V/C/X/A are dead in every text field, and the emoji palette cannot
    /// insert — so labels and snippet bodies could only ever receive typed characters.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Snip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "Emoji & Symbols",
                     action: #selector(NSApplication.orderFrontCharacterPalette(_:)), keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
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

    // The menu's single "Settings…" item opens the window on Snippets; the empty-wedge flow reuses openLibrary.
    @objc private func openLibrary() { openMainWindow(tab: .snippets) }
    @objc private func openSettings() { openMainWindow(tab: .snippets) }

    private func openMainWindow(tab: MainTab) {
        if mainWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 560),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Snip"
            // A dark, frosted HUD like the overlay: transparent titlebar, content edge to edge.
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.appearance = NSAppearance(named: .darkAqua)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView = NSHostingView(rootView: MainWindowView(
                model: model,
                updater: updater,
                onConfigChanged: { [weak self] in self?.updateRouting() },
                onRecordingChange: { [weak self] recording in self?.engine?.setPaused(recording) }))
            window.isReleasedWhenClosed = false
            // Resume the tap if the window closes mid-recording, so a paused tap can't get stranded.
            window.delegate = self
            window.center()
            mainWindow = window
        }
        model.mainTab = tab
        // Unlike the overlay, this window is meant to take focus.
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    /// The tap's event mask and trigger rules are fixed at creation, so a config change rebuilds it.
    private func restartEventTap() {
        engine?.stop()
        startEventTap()
    }

    /// A rule or global-trigger edit swaps the routing live. Unlike restartEventTap (used for a
    /// permission grant), this keeps the tap thread and its frontmost cache alive, so an edit made
    /// while Snip's window is frontmost doesn't reset the routed app to nil (the global trigger).
    private func updateRouting() {
        engine?.update(routing: model.triggerRouting)
    }

    private func startEventTap() {
        engine = EventTapEngine(
            routing: model.triggerRouting,
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
        guard case let .wedge(index) = selection else { return }
        if let snippet = model.snippet(inSlot: index) {
            paster.insert(snippet)
        } else {
            // Empty wedge: create a snippet for that position and jump straight to editing it. Reserve
            // it for editing BEFORE opening the window, so the library's onAppear purge sees the draft
            // as pending and spares it instead of deleting the very draft this fire is handing off.
            let id = model.createSnippet(inSlot: index)
            model.pendingEditSnippetID = id
            openLibrary()
        }
    }

    @objc private func grantAccessibility() {
        permissions.requestTrust()
        restartEventTap()
    }

    @MainActor @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

}

extension AppDelegate: NSWindowDelegate {
    /// Only the main window sets us as its delegate. If it closes mid-recording, the tap was left
    /// paused; resume it so the trigger keeps working. Resuming an already-live tap is a no-op.
    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === mainWindow else { return }
        engine?.setPaused(false)
    }
}

extension AppDelegate: NSMenuDelegate {
    /// Accessibility is granted once. Re-checked each time the menu opens, so the prompt (and its
    /// divider) hide as soon as we're trusted and reappear if the grant is ever revoked.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let trusted = permissions.isTrusted
        grantItem?.isHidden = trusted
        grantSeparator?.isHidden = trusted
    }
}
