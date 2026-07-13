// ABOUTME: The single Snip window: a centered segmented switch between Snippets, Trigger, Exceptions.
// ABOUTME: Replaces the separate Library and Settings windows; the frosted dark HUD is shared by all.
import SwiftUI

struct MainWindowView: View {
    @Bindable var model: AppModel
    var onConfigChanged: () -> Void
    var onRecordingChange: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().overlay(HUD.hairline)
            content
        }
        .background(HUDBackground())
        .frame(minWidth: 820, minHeight: 560)
        .preferredColorScheme(.dark)
    }

    /// Centered so the window's traffic lights float over the empty left of this bar.
    private var tabBar: some View {
        Picker("", selection: $model.mainTab) {
            Text("Snippets").tag(MainTab.snippets)
            Text("Trigger").tag(MainTab.trigger)
            Text("Exceptions").tag(MainTab.exceptions)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
        .frame(maxWidth: .infinity)
        .frame(height: 46)
    }

    @ViewBuilder private var content: some View {
        switch model.mainTab {
        case .snippets:
            LibraryView(model: model)
        case .trigger:
            TriggerSettingsView(model: model, onConfigChanged: onConfigChanged, onRecordingChange: onRecordingChange)
        case .exceptions:
            ExceptionsSettingsView(model: model, onConfigChanged: onConfigChanged)
        }
    }
}
