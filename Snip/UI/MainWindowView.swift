// ABOUTME: The single Snip window: a left sidebar (Snippets / Trigger / Exceptions) + the selected pane.
// ABOUTME: Replaces the separate Library and Settings windows; the solid dark ground is shared by all.
import SwiftUI

struct MainWindowView: View {
    @Bindable var model: AppModel
    var updater: UpdaterController
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
            footer
        }
        .padding(.horizontal, 10)
        .frame(width: 176, alignment: .top)
    }

    /// The etched footer plate at the sidebar's foot: version above, the site below. The build number
    /// stays off the face and lives in the version's tooltip.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Snip \(appVersion)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(HUD.textTertiary)
                .help("Build \(buildNumber)")
            Link("snip.hexul.com", destination: URL(string: "https://snip.hexul.com")!)
                .font(.system(size: 10))
                .foregroundStyle(HUD.textTertiary)
                .help("Open the Snip website")
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
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
            TriggerSettingsView(model: model, updater: updater, onConfigChanged: onConfigChanged, onRecordingChange: onRecordingChange)
        case .exceptions:
            ExceptionsSettingsView(model: model, onConfigChanged: onConfigChanged)
        }
    }
}
