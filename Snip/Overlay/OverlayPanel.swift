// ABOUTME: Borderless, non-activating panel that hosts the radial overlay.
// ABOUTME: DISPLAY-ONLY: ignoresMouseEvents is true because a consuming CGEventTap means mouse
// ABOUTME: events never reach any window. Never route radial selection through SwiftUI gestures.
import AppKit

final class OverlayPanel: NSPanel {
    /// v1.5 seam: the search palette needs typed input, which requires becoming key
    /// without activating the app (the Spotlight pattern). Unused in v1.
    var keyboardMode = false {
        didSet { ignoresMouseEvents = !keyboardMode }
    }

    override var canBecomeKey: Bool { keyboardMode }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        // The content is circular (NSVisualEffectView maskImage), so macOS derives a
        // circular window shadow from its alpha. A SwiftUI .shadow would come out square.
        hasShadow = true
        ignoresMouseEvents = true
        animationBehavior = .none
        // A floating HUD reads as dark regardless of the user's theme, like CleanShot's overlays.
        appearance = NSAppearance(named: .vibrantDark)
    }
}
