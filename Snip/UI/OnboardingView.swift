// ABOUTME: First-run window explaining and requesting the Accessibility permission.
// ABOUTME: Polls trust once a second so the tap can start without making the user relaunch.
import SwiftUI
import AppKit

struct OnboardingView: View {
    let isTrusted: () -> Bool
    let requestTrust: () -> Void
    let onGranted: () -> Void

    @State private var granted = false
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            Text("Snip needs Accessibility access")
                .font(.title2).bold()

            Text("It is required to notice the middle-mouse hold and to paste snippets into other apps. Snip never reads your screen or your keystrokes.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if granted {
                Label("Access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Open Accessibility Settings…") { requestTrust() }
                    .buttonStyle(.borderedProminent)
                Text("If the switch does not take effect, quit and reopen Snip.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(width: 460)
        .onReceive(poll) { _ in
            guard !granted, isTrusted() else { return }
            granted = true
            onGranted()
        }
    }
}
