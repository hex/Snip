// ABOUTME: SwiftUI settings for how the radial menu is triggered and where it is suppressed.
// ABOUTME: Changes persist through AppModel and restart the event tap via onConfigChanged.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var model: AppModel
    var onConfigChanged: () -> Void

    var body: some View {
        Form {
            Section("Trigger") {
                Toggle("Hold the middle mouse button", isOn: $model.triggerConfig.middleMouseEnabled)
                Text("While held, the ring opens under your cursor. Drag to a wedge and release to insert. Release in the middle to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Suppress in these apps") {
                if model.ignoredApps.isEmpty {
                    Text("Snip captures the middle button everywhere. Add apps here to let it through — for apps where middle-click means something (Blender orbit, a browser's new tab).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.ignoredApps) { app in
                        HStack {
                            Text(app.name)
                            Spacer()
                            Button {
                                remove(app)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button("Add Application…", action: addApplication)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 380)
        .onChange(of: model.triggerConfig) { _, _ in onConfigChanged() }
    }

    private func addApplication() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Suppress"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        guard !model.ignoredApps.contains(where: { $0.bundleID == bundleID }) else { return }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        model.ignoredApps.append(IgnoredApp(bundleID: bundleID, name: name))
        onConfigChanged()
    }

    private func remove(_ app: IgnoredApp) {
        model.ignoredApps.removeAll { $0.id == app.id }
        onConfigChanged()
    }
}
