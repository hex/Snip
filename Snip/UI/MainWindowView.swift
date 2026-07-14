// ABOUTME: The single Snip window: a left sidebar (Snippets / Trigger / Exceptions) + the selected pane.
// ABOUTME: Replaces the separate Library and Settings windows; the solid dark ground is shared by all.
import SwiftUI

struct MainWindowView: View {
    @Bindable var model: AppModel
    var onConfigChanged: () -> Void
    var onRecordingChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(HUD.hairline)
            content
        }
        .background(HUDBackground())
        .frame(minWidth: 900, minHeight: 520)
        .preferredColorScheme(.dark)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear.frame(height: 30)   // clear the window's floating traffic lights
            sidebarRow(.snippets, "Snippets", "text.insert")
            sidebarRow(.trigger, "Trigger", "cursorarrow.click")
            sidebarRow(.exceptions, "Exceptions", "hand.raised")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(width: 176, alignment: .top)
    }

    private func sidebarRow(_ tab: MainTab, _ title: String, _ icon: String) -> some View {
        let selected = model.mainTab == tab
        return HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 20)
                .foregroundStyle(selected ? HUD.signal : HUD.textSecondary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? HUD.textPrimary : HUD.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        // A pressed machined key, not a translucent tint fill.
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? HUD.raised : Color.clear))
        // The lit index bar: the instrument's selected-channel marker. Arc appears only as light.
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(HUD.signal)
                .frame(width: 2, height: 16)
                .opacity(selected ? 1 : 0)
        }
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture { model.mainTab = tab }
        .animation(.easeOut(duration: 0.16), value: selected)
    }

    // MARK: - Content

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
