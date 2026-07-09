// ABOUTME: A live, magnified view of the content behind the overlay window: a real loupe.
// ABOUTME: A private CABackdropLayer capture group (captureOnly provider + negative-zoom consumer).
import AppKit
import QuartzCore
import SwiftUI

/// Verified on macOS 26 (Tahoe): the WindowServer remaps the behind-window capture around the
/// consumer's centre by `contentScale = 1 / (1 + scale·zoom)`, so `zoom = (1/m − 1)/scale`
/// magnifies by `m`. Sharp, no filters, no portal, independent of the ring frost's backdrop group.
/// A CAPortalLayer + transform does NOT work: a windowServerAware backdrop always samples 1:1.
/// All private API. Gate on `isSupported`; the painted lens is the fallback.
final class BackdropLoupeView: NSView {

    var magnification: CGFloat = 1.5 {
        didSet { applyZoom() }
    }

    static var isSupported: Bool {
        NSClassFromString("CABackdropLayer") != nil
    }

    private let groupName = "BackdropLoupe." + UUID().uuidString
    private var provider: CALayer?
    private var consumer: CALayer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("BackdropLoupeView is created in code only") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { teardown() } else { wire() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyZoom()
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        provider?.frame = bounds
        consumer?.frame = bounds
        CATransaction.commit()
        applyZoom()
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
        p.frame = bounds
        let c = backdropClass.init()
        c.setValue(true, forKey: "windowServerAware")
        c.setValue(groupName, forKey: "groupName")
        c.frame = bounds
        host.addSublayer(p)
        host.addSublayer(c)
        CATransaction.commit()
        provider = p
        consumer = c
        applyZoom()
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

    /// Reports whether the loupe is wired, sharp, and its effective magnification, so the result
    /// can be confirmed from values rather than inferred from a screenshot.
    var healthReport: String {
        guard let c = consumer, let p = provider else { return "LOUPE: NOT WIRED (consumer=nil)" }
        let zoom = (c.value(forKey: "zoom") as? CGFloat) ?? 0
        let scale = (p.value(forKey: "scale") as? CGFloat) ?? 0
        let mag = 1 / (1 + scale * zoom)
        let sharp = (c.filters ?? []).isEmpty
        let inTree = c.superlayer === layer && p.superlayer === layer
        return "LOUPE: wired=\(inTree) sharp=\(sharp) providerScale=\(scale) zoom=\(String(format: "%.4f", zoom)) effectiveMag=\(String(format: "%.2f", mag))x"
    }
}

struct BackdropLoupe: NSViewRepresentable {
    var magnification: CGFloat = 1.5

    func makeNSView(context: Context) -> BackdropLoupeView {
        BackdropLoupeView(frame: .zero)
    }

    func updateNSView(_ view: BackdropLoupeView, context: Context) {
        view.magnification = magnification
    }
}
