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
    /// Fraction of extra magnification. 0.18 means the backdrop is shown at 1.18x.
    var magnification: Double = 0.18
    /// Barrel curvature at the rim, layered on top of the magnification.
    var curvature: Double = 0.32

    static var isSupported: Bool { NSClassFromString("CABackdropLayer") != nil }

    func makeNSView(context: Context) -> LensHostView {
        LensHostView(diameter: diameter, magnification: magnification, curvature: curvature)
    }

    func updateNSView(_ nsView: LensHostView, context: Context) {
        nsView.apply(diameter: diameter, magnification: magnification, curvature: curvature)
    }
}

final class LensHostView: NSView {
    private var backdrop: CALayer?

    init(diameter: CGFloat, magnification: Double, curvature: Double) {
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        wantsLayer = true
        // Without this, AppKit silently ignores Core Image filters anywhere in this layer tree.
        layerUsesCoreImageFilters = true
        layer?.masksToBounds = true
        layer?.cornerRadius = diameter / 2
        apply(diameter: diameter, magnification: magnification, curvature: curvature)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("LensHostView is created in code only") }

    func apply(diameter: CGFloat, magnification: Double, curvature: Double) {
        layer?.cornerRadius = diameter / 2

        if backdrop == nil { backdrop = makeBackdropLayer() }
        guard let backdrop else { return }   // class withdrawn: the painted lens still carries the look

        backdrop.frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        backdrop.cornerRadius = diameter / 2
        backdrop.masksToBounds = true

        // Two independent mechanisms, so losing either still leaves a lens:
        // `zoom` magnifies in the compositor, the filter curves the rim.
        backdrop.setValue(1.0 + magnification, forKey: "zoom")
        backdrop.filters = [bumpFilter(diameter: diameter, scale: curvature)].compactMap { $0 }
    }

    private func makeBackdropLayer() -> CALayer? {
        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type else { return nil }
        let layer = backdropClass.init()

        // Probed on macOS 26: windowServerAware, scale, zoom and captureOnly exist; disableBlur
        // and blurRadius do not. CALayer stores unknown keys rather than raising, so a withdrawn
        // property degrades to a harmless no-op instead of a crash.
        layer.setValue(true, forKey: "windowServerAware")
        layer.setValue(1.0, forKey: "scale")

        self.layer?.addSublayer(layer)
        return layer
    }

    private func bumpFilter(diameter: CGFloat, scale: Double) -> CIFilter? {
        guard let bump = CIFilter(name: "CIBumpDistortion") else { return nil }
        bump.setValue(CIVector(x: diameter / 2, y: diameter / 2), forKey: kCIInputCenterKey)
        bump.setValue(diameter / 2, forKey: kCIInputRadiusKey)
        bump.setValue(scale, forKey: kCIInputScaleKey)
        return bump
    }
}
