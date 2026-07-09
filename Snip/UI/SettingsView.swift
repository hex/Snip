// ABOUTME: SwiftUI settings for how the radial menu is triggered.
// ABOUTME: Changes persist through AppModel and restart the event tap via onConfigChanged.
import SwiftUI

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

            Section("Keyboard fallback") {
                Text("A configurable key chord arrives with the search palette, for trackpad users with no middle button.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 260)
        .onChange(of: model.triggerConfig) { _, _ in onConfigChanged() }
    }
}
