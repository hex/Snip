// ABOUTME: Executable entry point for the Snip menu-bar agent.
// ABOUTME: Boots NSApplication as an accessory (no Dock icon) with our AppDelegate.
import AppKit

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
