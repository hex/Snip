// ABOUTME: SwiftUI wrapper around NSVisualEffectView for CleanShot-style frosted vibrancy.
// ABOUTME: Clips via maskImage, because behindWindow blending ignores SwiftUI's clipShape.
import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var diameter: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.circleMask(diameter: diameter)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.maskImage = Self.circleMask(diameter: diameter)
    }

    /// The WindowServer composites behind-window vibrancy outside the layer-mask path, so
    /// SwiftUI's clipShape leaves the material painting its full square bounds. maskImage clips it.
    private static func circleMask(diameter: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }
}
