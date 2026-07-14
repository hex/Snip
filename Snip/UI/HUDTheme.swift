// ABOUTME: The main window's dark-HUD design tokens: the "Detent" machined-instrument language.
// ABOUTME: One cool-graphite ramp climbed by depth-of-cut; the system accent is the only signal color.
import SwiftUI
import AppKit

/// The Detent language: the window is a dark-anodized instrument. Surfaces are depths of cut on one
/// cool-graphite ramp, edges are machined seams, and the one signal is the system accent, rendered as a
/// backlit rim and glow rather than a flat fill.
enum HUD {
    static let well = Color(hex: 0x0A0C0F)      // deepest recess: inset wells, the pit under the dial
    static let ground = Color(hex: 0x0E1116)    // window base plane; sidebar and content share it
    static let socket = Color(hex: 0x0A0C0F)    // recessed wells (the same depth as `well`)
    static let chamber = Color(hex: 0x141821)   // a resting surface / chip: the machined plate
    static let field = Color(hex: 0x191E27)     // a text input reading well: recessed, not a black slab
    static let raised = Color(hex: 0x212734)    // hover and selected machined-key fill
    static let ridge = Color(hex: 0x2A313E)     // brushed crown: the ring band's top, lit control bevels

    static let hairline = Color.white.opacity(0.09)   // the bright half of a machined seam / divider
    static let emphasis = Color.white.opacity(0.16)   // a boundary meant to be found
    static let seamDark = Color.black.opacity(0.40)   // the shadow half of a machined groove
    static let bevel = Color.white.opacity(0.28)      // polished specular crown highlight

    static let textPrimary = Color(hex: 0xE9ECF1)     // etched marking: primary body
    static let textSecondary = Color(hex: 0x9AA1AD)   // secondary labels
    static let textTertiary = Color(hex: 0x646B76)    // calibration caps
    static let textMuted = Color(hex: 0x454B54)       // placeholder / ghost etch

    /// The single signal: the lit bearing, the sidebar index bar, the focused-field underline, the
    /// caret. The macOS system accent. On the dial the selection reads as a backlit rim and glow, never
    /// a flat wedge fill.
    static let signal = Color(nsColor: .controlAccentColor)
    /// The hottest filament center of the lit bearing: the accent lifted toward white so the core keeps
    /// the accent's own hue on every setting instead of clashing with a fixed tint.
    static let signalCore = Color(nsColor: NSColor.controlAccentColor
        .usingColorSpace(.sRGB)?
        .blended(withFraction: 0.65, of: .white) ?? .white)
}

extension Color {
    init(hex: UInt) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// The window base plane: a dark anodized descent. A stationary window has only the desktop behind it,
/// so real vibrancy just samples random junk, a clean milled ground reads far more intentional.
struct HUDBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(hex: 0x12151B), Color(hex: 0x0A0C0F)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}
