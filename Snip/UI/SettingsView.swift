// ABOUTME: The Trigger and Exceptions settings panes, shown as tabs in the single Snip window.
// ABOUTME: Changes persist through AppModel and restart the tap via onConfigChanged.
import SwiftUI
import AppKit
import CoreGraphics
import UniformTypeIdentifiers
import SnipKit

// MARK: - Trigger

struct TriggerSettingsView: View {
    @Bindable var model: AppModel
    var onConfigChanged: () -> Void
    /// Pauses/resumes the event tap so a bound key/button reaches the recorder instead of the ring.
    var onRecordingChange: (Bool) -> Void

    @State private var isRecordingShortcut = false
    @State private var shortcutMonitor: Any?

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

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                FieldLabel("OPEN THE RING")
                VStack(spacing: 0) {
                    plateRow("Gesture") { gestureSegments }
                    Divider().overlay(HUD.hairline)
                    plateRow("Trigger") { triggerControl }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(HUD.chamber))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(HUD.hairline, lineWidth: 1))
            }

            Text(footerText)
                .font(.system(size: 12))
                .foregroundStyle(HUD.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 34, leading: 26, bottom: 22, trailing: 26))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: model.triggerConfig) { _, _ in onConfigChanged() }
        .onDisappear { if isRecordingShortcut { cancelRecording() } }
    }

    /// A titled row inside a plate: label at the left, its control flush right.
    private func plateRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(HUD.textSecondary)
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
    }

    /// The gesture picker as machined keys: the active segment seats as a raised key with a lit accent
    /// edge. The signal appears only as that thin edge of light, never as a flat filled segment.
    private var gestureSegments: some View {
        HStack(spacing: 3) {
            ForEach(Gesture.allCases) { gesture in
                let on = currentGesture == gesture
                Text(gesture.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(on ? HUD.textPrimary : HUD.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 6).fill(HUD.raised).opacity(on ? 1 : 0))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(HUD.signal.opacity(0.8), lineWidth: 1).opacity(on ? 1 : 0))
                    .contentShape(Rectangle())
                    .onTapGesture { setGesture(gesture) }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(HUD.field))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HUD.hairline, lineWidth: 1))
        .animation(.easeOut(duration: 0.12), value: currentGesture)
    }

    private var triggerControl: some View {
        HStack(spacing: 10) {
            Text(model.triggerConfig.label)
                .font(.system(size: 12))
                .foregroundStyle(HUD.textTertiary)
            Button(isRecordingShortcut ? recordingPrompt : "Record") { startRecordingShortcut() }
                .buttonStyle(MachinedKeyButtonStyle())
                .disabled(isRecordingShortcut)
                .opacity(isRecordingShortcut ? 0.6 : 1)
        }
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

    /// Sets the gesture and rebuilds the binding so the segments and label never disagree. Double-click
    /// needs a mouse button, so flipping a key binding to double-click defaults it to the middle button.
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
            return nil   // swallow the captured input so it doesn't act on the window
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
}

// MARK: - Exceptions

/// A pickable running app for the suppress list.
private struct RunningApp: Identifiable {
    let id: String   // bundle identifier
    let name: String
    let icon: NSImage
}

struct ExceptionsSettingsView: View {
    @Bindable var model: AppModel
    var onConfigChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                FieldLabel("SUPPRESS THE TRIGGER IN THESE APPS")

                if model.ignoredApps.isEmpty {
                    Text("Snip captures the trigger everywhere. Add apps to let it through — where the trigger already means something (Blender orbit, a browser's new tab).")
                        .font(.system(size: 13))
                        .foregroundStyle(HUD.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 520, alignment: .leading)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.ignoredApps.enumerated()), id: \.element.id) { index, app in
                            if index > 0 { Divider().overlay(HUD.hairline) }
                            appRow(app)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(HUD.chamber))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(HUD.hairline, lineWidth: 1))
                }

                addMenu
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 34, leading: 26, bottom: 22, trailing: 26))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func appRow(_ app: IgnoredApp) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: icon(forBundleID: app.bundleID))
                .resizable().frame(width: 18, height: 18)
            Text(app.name)
                .font(.system(size: 13))
                .foregroundStyle(HUD.textPrimary)
            Spacer()
            Button { remove(app) } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(HUD.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
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
        .buttonStyle(MachinedKeyButtonStyle())
        .fixedSize()
    }

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
