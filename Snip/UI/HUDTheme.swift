// ABOUTME: The Library's dark-HUD design tokens and its frosted (vibrancy) window background.
// ABOUTME: One cool-graphite hue climbed by lightness; the system accent is the only signal color.
import SwiftUI
import AppKit

/// The Library shares the live overlay's world: a dark, frosted heads-up surface. Tokens are named
/// for that world, not for a generic gray scale.
enum HUD {
    static let ground = Color(hex: 0x0E1013)      // the abyss behind the vibrancy
    static let socket = Color(hex: 0x0B0D10)      // recessed wells
    static let chamber = Color(hex: 0x171A20)     // a resting surface / chip
    static let field = Color(hex: 0x191D25)       // a text input surface: recessed, but not a black slab
    static let raised = Color(hex: 0x20242C)      // hover, selected fill

    static let hairline = Color.white.opacity(0.08)   // quiet edges and dividers
    static let emphasis = Color.white.opacity(0.16)   // a boundary that should be found

    static let textPrimary = Color(hex: 0xE9ECF1)
    static let textSecondary = Color(hex: 0x9AA1AD)
    static let textTertiary = Color(hex: 0x646B76)
    static let textMuted = Color(hex: 0x454B54)

    /// The single signal: selected chamber rim + glow, the active bearing, the caret. Nothing else.
    static let signal = Color.accentColor
}

extension Color {
    init(hex: UInt) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// A behind-window vibrancy layer so the Library reads as frosted glass, like the overlay. A thin
/// ground tint sits on top so blur still breathes through without washing out the content.
struct HUDBackground: View {
    var body: some View {
        VisualEffect(material: .hudWindow)
            .overlay(HUD.ground.opacity(0.55))
            .ignoresSafeArea()
    }
}

private struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
