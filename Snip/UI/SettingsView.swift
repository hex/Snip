// ABOUTME: SwiftUI settings for how the radial menu is triggered and where it is suppressed.
// ABOUTME: Tabbed (Trigger / Exceptions); changes persist through AppModel and restart the tap.
import SwiftUI
import AppKit
import CoreGraphics
import UniformTypeIdentifiers

/// A pickable running app for the suppress list.
private struct RunningApp: Identifiable {
    let id: String   // bundle identifier
    let name: String
    let icon: NSImage
}

struct SettingsView: View {
    @Bindable var model: AppModel
    var onConfigChanged: () -> Void

    @State private var isRecordingShortcut = false
    @State private var shortcutMonitor: Any?

    var body: some View {
        TabView {
            triggerTab
                .tabItem { Label("Trigger", systemImage: "cursorarrow.click") }
            exceptionsTab
                .tabItem { Label("Exceptions", systemImage: "hand.raised") }
        }
        .frame(width: 480, height: 340)
        .onChange(of: model.triggerConfig) { _, _ in onConfigChanged() }
    }

    // MARK: - Trigger

    private var triggerTab: some View {
        Form {
            Section {
                Toggle("Hold the middle mouse button", isOn: $model.triggerConfig.middleMouseEnabled)
            } footer: {
                Text("While held, the ring opens under your cursor. Drag to a wedge and release to insert; release in the middle to cancel.")
            }

            Section {
                Toggle("Hold a keyboard shortcut", isOn: $model.triggerConfig.hotkeyEnabled)
                shortcutRecorderRow
            } footer: {
                Text("While held, the ring opens under your cursor. Drag the mouse to a wedge and release the shortcut to insert; release near the center to cancel.")
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutRecorderRow: some View {
        HStack {
            Text("Shortcut")
            Spacer()
            Text(shortcutLabel)
                .foregroundStyle(.secondary)
            Button(isRecordingShortcut ? "Press a key…" : "Record") {
                startRecordingShortcut()
            }
            .disabled(isRecordingShortcut)
        }
    }

    private var shortcutLabel: String {
        modifierSymbols(for: model.triggerConfig.hotkeyModifiers) + model.triggerConfig.hotkeyKeyLabel
    }

    private func modifierSymbols(for flags: CGEventFlags) -> String {
        var symbols = ""
        if flags.contains(.maskControl) { symbols += "⌃" }
        if flags.contains(.maskAlternate) { symbols += "⌥" }
        if flags.contains(.maskShift) { symbols += "⇧" }
        if flags.contains(.maskCommand) { symbols += "⌘" }
        return symbols
    }

    private func startRecordingShortcut() {
        isRecordingShortcut = true
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            recordShortcut(from: event)
            return nil   // swallow the captured key so it doesn't type into Settings
        }
    }

    private func recordShortcut(from event: NSEvent) {
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        shortcutMonitor = nil
        isRecordingShortcut = false

        model.triggerConfig.hotkeyKeyCode = Int(event.keyCode)
        model.triggerConfig.hotkeyModifierRawValue = cgEventFlags(from: event.modifierFlags).rawValue
        model.triggerConfig.hotkeyKeyLabel = keyLabel(for: event.keyCode, characters: event.charactersIgnoringModifiers)
    }

    private func cgEventFlags(from modifiers: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        return flags
    }

    private func keyLabel(for keyCode: UInt16, characters: String?) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 53: return "Escape"
        case 51: return "Delete"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return characters?.uppercased() ?? "Key \(keyCode)"
        }
    }

    // MARK: - Exceptions

    private var exceptionsTab: some View {
        Form {
            Section {
                if model.ignoredApps.isEmpty {
                    Text("Snip captures the middle button everywhere. Add apps to let it through — where middle-click already means something (Blender orbit, a browser's new tab).")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.ignoredApps) { app in
                        HStack(spacing: 8) {
                            Image(nsImage: icon(forBundleID: app.bundleID))
                                .resizable().frame(width: 18, height: 18)
                            Text(app.name)
                            Spacer()
                            Button {
                                remove(app)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove")
                        }
                    }
                }
                addMenu
            } header: {
                Text("Suppress the trigger in these apps")
            }
        }
        .formStyle(.grouped)
    }

    private var addMenu: some View {
        Menu {
            Menu("Running Applications") {
                ForEach(runningApps) { app in
                    Button {
                        add(bundleID: app.id, name: app.name)
                    } label: {
                        Label { Text(app.name) } icon: { Image(nsImage: app.icon) }
                    }
                }
            }
            Button("Manually Select From Finder…", action: addFromFinder)
        } label: {
            Label("Add Application", systemImage: "plus")
        }
        .menuStyle(.button)
        .fixedSize()
    }

    // MARK: - Data

    /// Regular (Dock-showing) apps, minus Snip itself and ones already suppressed.
    private var runningApps: [RunningApp] {
        let existing = model.ignoredBundleIDs
        let selfID = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .compactMap { app -> RunningApp? in
                guard app.activationPolicy == .regular,
                      let id = app.bundleIdentifier, id != selfID, !existing.contains(id),
                      let name = app.localizedName, let icon = app.icon else { return nil }
                return RunningApp(id: id, name: name, icon: icon)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func icon(forBundleID id: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }

    private func addFromFinder() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Suppress"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        add(bundleID: bundleID, name: name)
    }

    private func add(bundleID: String, name: String) {
        guard !model.ignoredApps.contains(where: { $0.bundleID == bundleID }) else { return }
        model.ignoredApps.append(IgnoredApp(bundleID: bundleID, name: name))
        onConfigChanged()
    }

    private func remove(_ app: IgnoredApp) {
        model.ignoredApps.removeAll { $0.id == app.id }
        onConfigChanged()
    }
}
