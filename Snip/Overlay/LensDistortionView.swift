// ABOUTME: Bends the real pixels behind the hub, using the private CABackdropLayer that holds them.
// ABOUTME: Progressive enhancement: if the class is gone, the painted lens above it still reads.
import SwiftUI
import CoreImage
import QuartzCore

/// `CALayer.backgroundFilters` filters content beneath the layer *within its own window*, and our
/// window is transparent there, so it has nothing to bend. `CABackdropLayer` is the layer
/// `NSVisualEffectView` uses: it owns the WindowServer's copy of what is behind the window, so
/// `filters` (which act on a layer's own content) can distort it.
struct LensDistortionView: NSViewRepresentable {
    var diameter: CGFloat
    /// CIBumpDistortion input scale, 0...1. Higher bulges the centre more.
    var magnification: Double = 0.8

    static var isSupported: Bool { NSClassFromString("CABackdropLayer") != nil }

    func makeNSView(context: Context) -> LensHostView {
        LensHostView(diameter: diameter, magnification: magnification)
    }

    func updateNSView(_ nsView: LensHostView, context: Context) {
        nsView.apply(diameter: diameter, magnification: magnification)
    }
}

final class LensHostView: NSView {
    private let diameter: CGFloat
    private var magnification: Double

    init(diameter: CGFloat, magnification: Double) {
        self.diameter = diameter
        self.magnification = magnification
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        // Must be set before the backing layer is created, or Core Image filters are ignored.
        layerUsesCoreImageFilters = true
        wantsLayer = true          // triggers makeBackingLayer()
        apply(diameter: diameter, magnification: magnification)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("LensHostView is created in code only") }

    /// The backdrop must BE the view's layer, not a sublayer, so AppKit wires it into the
    /// window's backdrop group. Falls back to an ordinary layer if the class is withdrawn.
    override func makeBackingLayer() -> CALayer {
        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type else {
            return super.makeBackingLayer()
        }
        let layer = backdropClass.init()
        // Probed on macOS 26. CALayer stores unknown keys rather than raising, so a withdrawn
        // property degrades to a harmless no-op instead of a crash.
        layer.setValue(true, forKey: "windowServerAware")     // sample across the window server
        layer.setValue(true, forKey: "allowsInPlaceFiltering") // let `filters` composite on it
        layer.setValue(1.0, forKey: "scale")
        return layer
    }

    func apply(diameter: CGFloat, magnification: Double) {
        self.magnification = magnification
        guard let layer else { return }
        layer.masksToBounds = true
        layer.cornerRadius = diameter / 2
        layer.filters = [bumpFilter(diameter: diameter, scale: magnification)].compactMap { $0 }
    }

    /// CIBumpDistortion magnifies the centre and curves the rim. A public filter whose units are
    /// documented, unlike CABackdropLayer's `zoom` (which defaults to 0, not 1).
    private func bumpFilter(diameter: CGFloat, scale: Double) -> CIFilter? {
        guard let bump = CIFilter(name: "CIBumpDistortion") else { return nil }
        bump.setValue(CIVector(x: diameter / 2, y: diameter / 2), forKey: kCIInputCenterKey)
        bump.setValue(diameter / 2, forKey: kCIInputRadiusKey)
        bump.setValue(scale, forKey: kCIInputScaleKey)
        return bump
    }
}
