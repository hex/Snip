// ABOUTME: The Trigger and Apps settings panes, shown as tabs in the single Snip window.
// ABOUTME: Changes persist through AppModel and restart the tap via onConfigChanged.
import SwiftUI
import AppKit
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers
import SnipKit

// MARK: - Trigger

struct TriggerSettingsView: View {
    @Bindable var model: AppModel
    @Bindable var updater: UpdaterController
    var onConfigChanged: () -> Void
    /// Pauses/resumes the event tap so a bound key/button reaches the recorder instead of the ring.
    var onRecordingChange: (Bool) -> Void

    @State private var isRecordingShortcut = false
    @State private var shortcutMonitor: Any?
    @State private var startsAtLogin = SMAppService.mainApp.status == .enabled

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

            VStack(alignment: .leading, spacing: 12) {
                FieldLabel("APPLICATION")
                VStack(spacing: 0) {
                    plateRow("Start at login") {
                        Toggle("", isOn: Binding(get: { startsAtLogin }, set: { setStartAtLogin($0) }))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .tint(HUD.signal)
                    }
                    Divider().overlay(HUD.hairline)
                    plateRow("Automatically check for updates") {
                        Toggle("", isOn: $updater.automaticallyChecksForUpdates)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .tint(HUD.signal)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(HUD.chamber))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(HUD.hairline, lineWidth: 1))
            }

            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 34, leading: 26, bottom: 22, trailing: 26))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: model.triggerConfig) { _, _ in onConfigChanged() }
        .onAppear { startsAtLogin = SMAppService.mainApp.status == .enabled }
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

    /// Registers or unregisters Snip as a login item, then re-reads launchd's actual status. System
    /// Settings owns the same switch, so the status query is the source of truth: a failed or pending
    /// change snaps the toggle back instead of showing a state that isn't real.
    private func setStartAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // The re-read below reverts the toggle; there is no other surface to report the error on.
        }
        startsAtLogin = SMAppService.mainApp.status == .enabled
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
                model.triggerConfig.label = TriggerCapture.mouseButtonLabel(for: n)
            }
        case .doubleClick:
            switch model.triggerConfig.binding {
            case .holdMouseButton(let n), .doubleClickMouseButton(let n):
                model.triggerConfig.binding = .doubleClickMouseButton(n)
                model.triggerConfig.label = TriggerCapture.mouseButtonLabel(for: n)
            case .holdKey:
                model.triggerConfig.binding = .doubleClickMouseButton(2)
                model.triggerConfig.label = TriggerCapture.mouseButtonLabel(for: 2)
            }
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

        if currentGesture == .doubleClick {
            guard event.type == .otherMouseDown else { return }   // the mask should exclude keys anyway
            model.triggerConfig.binding = .doubleClickMouseButton(event.buttonNumber)
            model.triggerConfig.label = TriggerCapture.mouseButtonLabel(for: event.buttonNumber)
        } else if let captured = TriggerCapture.holdBinding(from: event) {
            model.triggerConfig.binding = captured.binding
            model.triggerConfig.label = captured.label
        }
    }
}

// MARK: - Apps

/// A pickable running app for the per-app rules list.
private struct RunningApp: Identifiable {
    let id: String   // bundle identifier
    let name: String
    let icon: NSImage
}

struct AppsSettingsView: View {
    @Bindable var model: AppModel
    var onConfigChanged: () -> Void
    /// Pauses/resumes the event tap so a bound key/button reaches the recorder instead of the ring.
    var onRecordingChange: (Bool) -> Void

    /// The rule whose Record button is armed; nil when nothing is recording.
    @State private var recordingBundleID: String?
    @State private var recordMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                FieldLabel("PER-APP RULES")

                if model.appRules.isEmpty {
                    Text("Snip opens on your trigger everywhere. Add an app to change that there: suppress the trigger where it already means something (Blender orbit, a browser's new tab), or open the ring on a different trigger.")
                        .font(.system(size: 13))
                        .foregroundStyle(HUD.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 520, alignment: .leading)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.appRules.enumerated()), id: \.element.id) { index, rule in
                            if index > 0 { Divider().overlay(HUD.hairline) }
                            ruleRow(rule)
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
        .onDisappear { if recordingBundleID != nil { cancelRecording() } }
    }

    private func ruleRow(_ rule: AppRule) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: icon(forBundleID: rule.bundleID))
                .resizable().frame(width: 18, height: 18)
            Text(rule.name)
                .font(.system(size: 13))
                .foregroundStyle(HUD.textPrimary)
            Spacer()
            if case let .trigger(config) = rule.behavior {
                Text(recordingBundleID == rule.bundleID ? "Press a key or mouse button…" : config.label)
                    .font(.system(size: 12))
                    .foregroundStyle(HUD.textTertiary)
                Button("Record") { startRecording(for: rule.bundleID) }
                    .buttonStyle(MachinedKeyButtonStyle())
                    .disabled(recordingBundleID != nil)
                    .opacity(recordingBundleID == rule.bundleID ? 0.6 : 1)
            }
            behaviorMenu(for: rule)
            Button { remove(rule) } label: {
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

    /// Suppress or a custom trigger. Choosing a custom trigger arms the recorder immediately, so the
    /// choice flows straight into "press the trigger you want here".
    private func behaviorMenu(for rule: AppRule) -> some View {
        Menu {
            Button("Suppress") { setBehavior(.suppress, for: rule.bundleID) }
            Button("Custom Trigger") {
                if case .trigger = rule.behavior { return }
                setBehavior(.trigger(TriggerConfig()), for: rule.bundleID)
                startRecording(for: rule.bundleID)
            }
        } label: {
            Text(menuTitle(for: rule.behavior))
        }
        .menuStyle(.button)
        .buttonStyle(MachinedKeyButtonStyle())
        .fixedSize()
    }

    private func menuTitle(for behavior: AppBehavior) -> String {
        switch behavior {
        case .suppress: return "Suppress"
        case .trigger: return "Custom Trigger"
        }
    }

    private func setBehavior(_ behavior: AppBehavior, for bundleID: String) {
        guard let index = model.appRules.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        model.appRules[index].behavior = behavior
        onConfigChanged()
    }

    private func startRecording(for bundleID: String) {
        recordingBundleID = bundleID
        onRecordingChange(true)   // pause the tap so the pressed input reaches this monitor
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .otherMouseDown]) { event in
            record(event)
            return nil   // swallow the captured input so it doesn't act on the window
        }
    }

    /// Removes the monitor and resumes the tap without recording anything (abandoned recording).
    private func cancelRecording() {
        if let recordMonitor { NSEvent.removeMonitor(recordMonitor) }
        recordMonitor = nil
        recordingBundleID = nil
        onRecordingChange(false)
    }

    private func record(_ event: NSEvent) {
        guard let bundleID = recordingBundleID else { return }
        cancelRecording()
        guard let captured = TriggerCapture.holdBinding(from: event) else { return }
        setBehavior(.trigger(TriggerConfig(binding: captured.binding, label: captured.label)), for: bundleID)
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

    /// Regular (Dock-showing) apps, minus Snip itself and ones that already have a rule.
    private var runningApps: [RunningApp] {
        let existing = Set(model.appRules.map(\.bundleID))
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
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        add(bundleID: bundleID, name: name)
    }

    /// New rules start as suppress, the choice that needs no further input; the row's menu switches
    /// it to a custom trigger.
    private func add(bundleID: String, name: String) {
        guard !model.appRules.contains(where: { $0.bundleID == bundleID }) else { return }
        model.appRules.append(AppRule(bundleID: bundleID, name: name, behavior: .suppress))
        onConfigChanged()
    }

    private func remove(_ rule: AppRule) {
        model.appRules.removeAll { $0.id == rule.id }
        onConfigChanged()
    }
}
