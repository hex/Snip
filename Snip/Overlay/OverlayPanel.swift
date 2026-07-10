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

    /// AppKit nudges windows back on screen by default. The ring must stay centered on the
    /// cursor even at a screen edge, or the drawn wedges stop matching the drag geometry.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        // Above everything, including apps in "traditional" (non-native) fullscreen that raise
        // their own window to a high level to cover the menu bar (e.g. iTerm). .screenSaver was
        // not enough. .canJoinAllSpaces still covers native fullscreen (its own Space).
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        // The WindowServer snapshots a window shadow from the content's alpha at one instant, so
        // an animating ring drags a stale dark ring behind it. The view draws its own shadow.
        hasShadow = false
        ignoresMouseEvents = true
        animationBehavior = .none
        // A floating HUD reads as dark regardless of the user's theme, like CleanShot's overlays.
        appearance = NSAppearance(named: .vibrantDark)
    }
}
