// ABOUTME: SwiftUI wrapper around NSVisualEffectView for CleanShot-style frosted vibrancy.
// ABOUTME: Masked to an annulus, so the hub is a real see-through hole rather than more material.
import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    /// Outer diameter of the glass ring.
    var diameter: CGFloat
    /// Diameter of the see-through hub, as a fraction of `diameter`.
    var holeFraction: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.annulusMask(diameter: diameter, holeFraction: holeFraction)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.maskImage = Self.annulusMask(diameter: diameter, holeFraction: holeFraction)
    }

    /// The WindowServer composites behind-window vibrancy outside the layer-mask path, so
    /// SwiftUI's clipShape cannot cut it. maskImage is the only thing that shapes the material.
    private static func annulusMask(diameter: CGFloat, holeFraction: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: rect).fill()

            // Punch the hub out so the user's document shows through, unblurred.
            let side = rect.width * holeFraction
            let hole = NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: hole).fill()
            return true
        }
    }
}
