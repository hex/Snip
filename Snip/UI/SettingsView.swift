// ABOUTME: SwiftUI settings for how the radial menu is triggered and where it is suppressed.
// ABOUTME: Tabbed (Trigger / Exceptions); changes persist through AppModel and restart the tap.
import SwiftUI
import AppKit
import CoreGraphics
import UniformTypeIdentifiers
import SnipKit

/// A pickable running app for the suppress list.
private struct RunningApp: Identifiable {
    let id: String   // bundle identifier
    let name: String
    let icon: NSImage
}

struct SettingsView: View {
    @Bindable var model: AppModel
    var onConfigChanged: () -> Void
    /// Pauses/resumes the event tap so a bound key/button reaches the recorder instead of the ring.
    var onRecordingChange: (Bool) -> Void

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
        .onDisappear { if isRecordingShortcut { cancelRecording() } }
    }

    // MARK: - Trigger

    /// The two ways to arm the trigger. A key or a mouse button can be held; only a mouse button can
    /// be double-clicked (with its second press held).
    private enum Gesture: String, CaseIterable, Identifiable {
        case hold = "Hold"
        case doubleClick = "Double-click"
        var id: String { rawValue }
    }

    private var currentGesture: Gesture {
        if case .doubleClickMouseButton = model.triggerConfig.binding { return .doubleClick }
        return .hold
    }

    private var triggerTab: some View {
        Form {
            Section {
                Picker("Gesture", selection: gestureBinding) {
                    ForEach(Gesture.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Trigger")
                    Spacer()
                    Text(model.triggerConfig.label)
                        .foregroundStyle(.secondary)
                    Button(isRecordingShortcut ? recordingPrompt : "Record") {
                        startRecordingShortcut()
                    }
                    .disabled(isRecordingShortcut)
                }
            } header: {
                Text("Open the ring")
            } footer: {
                Text(footerText)
            }
        }
        .formStyle(.grouped)
    }

    private var recordingPrompt: String {
        currentGesture == .doubleClick ? "Click a mouse button…" : "Press a key or mouse button…"
    }

    private var footerText: String {
        switch currentGesture {
        case .hold:
            return "Hold your trigger to open the ring under the cursor, drag to a wedge, and release to insert. Release in the middle to cancel. Record a keyboard shortcut, the middle button, or a side/thumb button."
        case .doubleClick:
            return "Double-click your mouse button and keep the second press held: the ring opens under the cursor. Drag to a wedge and release to insert; release in the middle to cancel."
        }
    }

    /// Reads the gesture from the stored binding and, on change, rebuilds the binding so the picker and
    /// label never disagree. Double-click needs a mouse button, so flipping a key binding to
    /// double-click defaults it to the middle button.
    private var gestureBinding: Binding<Gesture> {
        Binding(get: { currentGesture }, set: { setGesture($0) })
    }

    private func setGesture(_ gesture: Gesture) {
        switch gesture {
        case .hold:
            if case let .doubleClickMouseButton(n) = model.triggerConfig.binding {
                model.triggerConfig.binding = .holdMouseButton(n)
                model.triggerConfig.label = mouseButtonLabel(for: n)
            }
        case .doubleClick:
            switch model.triggerConfig.binding {
            case .holdMouseButton(let n), .doubleClickMouseButton(let n):
                model.triggerConfig.binding = .doubleClickMouseButton(n)
                model.triggerConfig.label = mouseButtonLabel(for: n)
            case .holdKey:
                model.triggerConfig.binding = .doubleClickMouseButton(2)
                model.triggerConfig.label = mouseButtonLabel(for: 2)
            }
        }
    }

    private func modifierSymbols(for flags: CGEventFlags) -> String {
        var symbols = ""
        if flags.contains(.maskControl) { symbols += "⌃" }
        if flags.contains(.maskAlternate) { symbols += "⌥" }
        if flags.contains(.maskShift) { symbols += "⇧" }
        if flags.contains(.maskCommand) { symbols += "⌘" }
        return symbols
    }

    private func mouseButtonLabel(for button: Int) -> String {
        switch button {
        case 2: return "Middle Button"
        default: return "Button \(button + 1)"   // buttonNumber is 0-indexed; people count from 1
        }
    }

    private func startRecordingShortcut() {
        isRecordingShortcut = true
        onRecordingChange(true)   // pause the tap so the pressed input reaches this monitor
        // Double-click can only bind a mouse button; hold can bind a key or a mouse button.
        let mask: NSEvent.EventTypeMask = currentGesture == .doubleClick
            ? [.otherMouseDown]
            : [.keyDown, .otherMouseDown]
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            recordTrigger(from: event)
            return nil   // swallow the captured input so it doesn't act on Settings
        }
    }

    /// Removes the monitor and resumes the tap without recording anything (abandoned recording).
    private func cancelRecording() {
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        shortcutMonitor = nil
        isRecordingShortcut = false
        onRecordingChange(false)
    }

    private func recordTrigger(from event: NSEvent) {
        cancelRecording()

        let doubleClick = currentGesture == .doubleClick
        switch event.type {
        case .keyDown where !doubleClick:
            let modifiers = cgEventFlags(from: event.modifierFlags)
            model.triggerConfig.binding = .holdKey(code: Int(event.keyCode), modifierRawValue: modifiers.rawValue)
            model.triggerConfig.label = modifierSymbols(for: modifiers)
                + keyLabel(for: event.keyCode, characters: event.charactersIgnoringModifiers)
        case .otherMouseDown:
            let button = event.buttonNumber
            model.triggerConfig.binding = doubleClick ? .doubleClickMouseButton(button) : .holdMouseButton(button)
            model.triggerConfig.label = mouseButtonLabel(for: button)
        default:
            break   // a key in double-click mode: ignored (the mask should exclude it anyway)
        }
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
                    Text("Snip captures the trigger everywhere. Add apps to let it through — where the trigger already means something (Blender orbit, a browser's new tab).")
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
