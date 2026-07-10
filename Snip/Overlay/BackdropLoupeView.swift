// ABOUTME: A live, magnified, barrel-distorted view of the content behind the overlay window.
// ABOUTME: A CABackdropLayer capture group (captureOnly provider + negative-zoom consumer) plus a
// ABOUTME: native displacementMap CAFilter for the physical-lens rim curvature.
import AppKit
import QuartzCore
import SwiftUI

/// Verified on macOS 26 (Tahoe). Magnification: the WindowServer remaps the behind-window capture
/// around the consumer's centre by `contentScale = 1/(1 + scale·zoom)`, so `zoom = (1/m − 1)/scale`
/// magnifies by `m`. Edge distortion: a native `displacementMap` CAFilter (found via CAFilter's
/// `-inputKeys`) bends the sampled coordinates radially, quadratically toward the rim. Both render
/// server-side, sharp, no Screen Recording. All private API; gate on the `isSupported` checks.
/// A CAPortalLayer + transform does NOT magnify a backdrop, and CIFilters never run on one.
final class BackdropLoupeView: NSView {

    var magnification: CGFloat = 1.5 { didSet { applyZoom() } }

    /// Barrel/edge lens curvature as a fraction of the loupe radius.
    /// 0 = flat magnifier; ~0.45 = pronounced physical-lens rim refraction.
    /// Silently ignored (flat loupe) when the private displacement filter is unavailable.
    var lensDistortion: CGFloat = 0.42 { didSet { needsLayout = true } }

    static var isSupported: Bool { NSClassFromString("CABackdropLayer") != nil }

    /// Whether the private `CAFilter` displacementMap with the expected input keys exists.
    /// Swift cannot catch the NSException a bad KVC key throws, so never set a key not in inputKeys.
    static let distortionSupported: Bool = {
        guard let cls = NSClassFromString("CAFilter") as? NSObject.Type else { return false }
        let sel = NSSelectorFromString("filterWithType:")
        guard cls.responds(to: sel),
              let f = cls.perform(sel, with: "displacementMap")?.takeUnretainedValue() as? NSObject
        else { return false }
        let keys = (f.perform(NSSelectorFromString("inputKeys"))?.takeUnretainedValue() as? [String]) ?? []
        return keys.contains("inputMaskImage") && keys.contains("inputAmount") && keys.contains("inputOffset")
    }()

    private let groupName = "BackdropLoupe." + UUID().uuidString
    private var provider: CALayer?
    private var consumer: CALayer?
    private let aperture = CAShapeLayer()
    private var mapCachePx = 0
    private var mapCache: CGImage?

    private var distortionActive: Bool { lensDistortion > 0.001 && Self.distortionSupported }
    /// Capture margin (fraction of radius) so rim displacement samples real content, not transparency.
    private var marginFactor: CGFloat { distortionActive ? 0.4 : 0 }

    private var revealed = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.opacity = 0                 // the reveal animation fades and irises it in
        aperture.fillColor = NSColor.black.cgColor
        layer?.mask = aperture
    }

    /// Iris the lens open (elastic mask scale + fade) instead of transforming the backdrop, which
    /// re-samples at the end of a transform and looks like a snap. The magnified content stays put;
    /// the circular window grows. Reused across the transient panel's show/hide cycles.
    func setRevealed(_ shown: Bool) {
        guard shown != revealed else { return }
        revealed = shown
        guard let host = layer else { return }
        host.removeAnimation(forKey: "fade")
        aperture.removeAnimation(forKey: "iris")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = host.presentation()?.opacity ?? host.opacity

        if shown {
            fade.toValue = 1
            fade.duration = 0.26
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            host.opacity = 1
            host.add(fade, forKey: "fade")

            let iris = CASpringAnimation(keyPath: "transform.scale")
            iris.fromValue = 0.35
            iris.toValue = 1
            iris.damping = 13
            iris.stiffness = 170
            iris.mass = 1
            iris.initialVelocity = 3
            iris.duration = iris.settlingDuration
            aperture.transform = CATransform3DIdentity
            aperture.add(iris, forKey: "iris")
        } else {
            fade.toValue = 0
            fade.duration = 0.13
            fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
            host.opacity = 0
            host.add(fade, forKey: "fade")
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("BackdropLoupeView is created in code only") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { teardown() } else { wire() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        mapCachePx = 0   // backing scale changed: rebuild the map at the new resolution
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let margin = (bounds.width / 2) * marginFactor
        let layerFrame = bounds.insetBy(dx: -margin, dy: -margin)
        provider?.frame = layerFrame
        consumer?.frame = layerFrame
        aperture.frame = bounds
        aperture.path = CGPath(ellipseIn: bounds, transform: nil)   // visible circular aperture
        CATransaction.commit()
        applyZoom()
        applyDistortion()
    }

    private func wire() {
        guard consumer == nil, Self.isSupported, let host = layer,
              let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let p = backdropClass.init()
        p.setValue(true, forKey: "captureOnly")
        p.setValue(true, forKey: "windowServerAware")
        p.setValue(groupName, forKey: "groupName")
        let c = backdropClass.init()
        c.setValue(true, forKey: "windowServerAware")
        c.setValue(groupName, forKey: "groupName")
        host.addSublayer(p)
        host.addSublayer(c)
        CATransaction.commit()
        provider = p
        consumer = c
        needsLayout = true
    }

    private func teardown() {
        provider?.removeFromSuperlayer()
        consumer?.removeFromSuperlayer()
        provider = nil
        consumer = nil
    }

    private func applyZoom() {
        guard let provider, let consumer else { return }
        let scale = window?.backingScaleFactor ?? 2
        provider.setValue(scale, forKey: "scale")
        let m = max(magnification, 0.01)   // zoom must stay > -1/scale (the formula's pole)
        consumer.setValue((1 / m - 1) / scale, forKey: "zoom")
    }

    private func applyDistortion() {
        guard let consumer else { return }
        guard distortionActive else { consumer.filters = []; return }
        let scale = window?.backingScaleFactor ?? 2
        let px = Int((consumer.bounds.width * scale).rounded())
        guard px > 0 else { consumer.filters = []; return }
        if px != mapCachePx { mapCache = Self.barrelMap(diameterPx: px); mapCachePx = px }
        guard let map = mapCache,
              let filter = Self.displacementFilter(map: map, amount: lensDistortion * (bounds.width / 2)) else {
            consumer.filters = []   // graceful fallback to the flat magnifier
            return
        }
        consumer.filters = [filter]
    }

    /// A radial barrel displacement map: R,G encode a signed radial vector (0.5 = neutral, growing
    /// quadratically toward the rim, pointing outward), B/A = 255 (B=128 washes out to 50% alpha).
    /// Paired with `inputOffset = (0.5, 0.5)` so the centre is undisplaced.
    private static func barrelMap(diameterPx: Int) -> CGImage? {
        let w = diameterPx, h = diameterPx
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        let buf = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        let cx = Double(w) / 2, cy = Double(h) / 2, radius = Double(w) / 2
        for y in 0..<h {
            for x in 0..<w {
                let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                let r = (dx * dx + dy * dy).squareRoot() / radius
                var ux = 0.0, uy = 0.0
                if r > 1e-4 { ux = dx / (r * radius); uy = dy / (r * radius) }
                let mag = r * r
                let sx = 0.5 + 0.5 * mag * ux
                let sy = 0.5 + 0.5 * mag * uy
                let i = (y * w + x) * 4
                buf[i]     = UInt8((255 * min(1, max(0, sx))).rounded())
                buf[i + 1] = UInt8((255 * min(1, max(0, sy))).rounded())
                buf[i + 2] = 255
                buf[i + 3] = 255
            }
        }
        return ctx.makeImage()
    }

    private static func displacementFilter(map: CGImage, amount: CGFloat) -> NSObject? {
        guard let cls = NSClassFromString("CAFilter") as? NSObject.Type else { return nil }
        let sel = NSSelectorFromString("filterWithType:")
        guard cls.responds(to: sel),
              let f = cls.perform(sel, with: "displacementMap")?.takeUnretainedValue() as? NSObject
        else { return nil }
        let keys = (f.perform(NSSelectorFromString("inputKeys"))?.takeUnretainedValue() as? [String]) ?? []
        guard keys.contains("inputMaskImage"), keys.contains("inputAmount"), keys.contains("inputOffset")
        else { return nil }
        f.setValue(map, forKey: "inputMaskImage")
        f.setValue(amount, forKey: "inputAmount")
        f.setValue(NSValue(point: NSPoint(x: 0.5, y: 0.5)), forKey: "inputOffset")
        return f
    }

    /// Reports magnification, distortion support, and active filters from live layer values.
    var healthReport: String {
        guard let c = consumer, let p = provider else { return "LOUPE: NOT WIRED" }
        let zoom = (c.value(forKey: "zoom") as? CGFloat) ?? 0
        let scale = (p.value(forKey: "scale") as? CGFloat) ?? 0
        let mag = 1 / (1 + scale * zoom)
        let filters = (c.filters ?? []).compactMap { ($0 as AnyObject).value(forKey: "type") as? String }
        return "LOUPE: mag=\(String(format: "%.2f", mag))x distortSupported=\(Self.distortionSupported) filters=\(filters)"
    }
}

struct BackdropLoupe: NSViewRepresentable {
    var magnification: CGFloat = 1.5
    var lensDistortion: CGFloat = 0.42
    /// Drives the elastic iris + fade; the loupe self-animates rather than being scaled by SwiftUI.
    var revealed: Bool = false

    func makeNSView(context: Context) -> BackdropLoupeView {
        BackdropLoupeView(frame: .zero)
    }

    func updateNSView(_ view: BackdropLoupeView, context: Context) {
        view.magnification = magnification
        view.lensDistortion = lensDistortion
        view.setRevealed(revealed)
    }
}
