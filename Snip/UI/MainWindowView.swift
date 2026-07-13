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
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(selected ? HUD.textPrimary : HUD.textSecondary)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? HUD.signal.opacity(0.20) : Color.clear))
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture { model.mainTab = tab }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch model.mainTab {
        case .snippets:
            LibraryView(model: model)
        case .trigger:
            TriggerSettingsView(model: model, onConfigChanged: onConfigChanged, onRecordingChange: onRecordingChange)
                .padding(.top, 22)
        case .exceptions:
            ExceptionsSettingsView(model: model, onConfigChanged: onConfigChanged)
                .padding(.top, 22)
        }
    }
}
