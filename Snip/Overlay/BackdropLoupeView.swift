// ABOUTME: A live, magnified view of the OTHER apps' pixels behind the overlay window: a real loupe.
// ABOUTME: Rendered by the WindowServer (no Screen Recording), via private CAPortalLayer + CABackdropLayer.
import AppKit
import QuartzCore
import SwiftUI

/// Approach verified on macOS 26 (Tahoe): a `CAPortalLayer` mirroring a real, AppKit-wired
/// `NSVisualEffectView` backdrop re-renders the live behind-window feed AND honors transforms,
/// so scaling the portal magnifies it. A hand-rolled CABackdropLayer receives nothing, and the
/// backdrop's own `zoom` only zooms out, so the portal is the only route to a magnify-in loupe.
/// All private API. Gate on `isSupported`; the painted lens is the fallback.
final class BackdropLoupeView: NSView {
    var magnification: CGFloat = 1.5 {
        didSet { portal?.transform = CATransform3DMakeScale(magnification, magnification, 1) }
    }

    static var isSupported: Bool {
        NSClassFromString("CAPortalLayer") is CALayer.Type && NSClassFromString("CABackdropLayer") != nil
    }

    private let source = SourceEffectView()
    private var portal: CALayer?
    private var wireAttempts = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true            // circular clip for the loupe content
        source.frame = bounds
        source.autoresizingMask = [.width, .height]
        source.material = .hudWindow
        source.blendingMode = .behindWindow    // makes AppKit register + wire the backdrop
        source.state = .active
        addSubview(source)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("BackdropLoupeView is created in code only") }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        portal?.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, portal == nil, Self.isSupported else { return }
        wireAttempts = 0
        scheduleWire()
    }

    private func scheduleWire() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.wire() }
    }

    private func wire() {
        guard portal == nil, window != nil, let host = layer, let srcLayer = source.layer,
              let backdrop = Self.backdropLayers(in: srcLayer).first
        else {
            wireAttempts += 1
            if wireAttempts < 40, window != nil { scheduleWire() }   // backdrop is built lazily
            return
        }
        source.strip()
        sharpenWindowCapture()

        guard let portalClass = NSClassFromString("CAPortalLayer") as? CALayer.Type else { return }
        let p = portalClass.init()
        p.setValue(true, forKey: "allowsBackdropGroups")
        p.setValue(backdrop, forKey: "sourceLayer")
        p.setValue(true, forKey: "hidesSourceLayer")
        p.bounds = backdrop.bounds
        p.position = CGPoint(x: bounds.midX, y: bounds.midY)
        p.transform = CATransform3DMakeScale(magnification, magnification, 1)
        host.addSublayer(p)
        portal = p
    }

    /// The window-root capture provider samples at 0.125x (blur-grade). Raise it to the backing
    /// scale so a magnified loupe stays sharp. Side effect: the ring's frost sharpens too, so scale
    /// every consumer's gaussianBlur radius to keep the frost looking the same.
    private func sharpenWindowCapture() {
        guard var root = layer else { return }
        while let parent = root.superlayer { root = parent }
        let all = Self.backdropLayers(in: root)
        guard let provider = all.first(where: { ($0.value(forKey: "captureOnly") as? Bool) == true }),
              let old = provider.value(forKey: "scale") as? CGFloat else { return }
        let new = window?.backingScaleFactor ?? 2
        guard old < new else { return }
        provider.setValue(new, forKey: "scale")
        for consumer in all where consumer !== provider {
            for filter in consumer.filters ?? [] {
                let f = filter as AnyObject
                if (f.value(forKey: "name") as? String) == "gaussianBlur",
                   let radius = f.value(forKey: "inputRadius") as? CGFloat {
                    f.setValue(radius * new / old, forKey: "inputRadius")
                }
            }
        }
    }

    static func backdropLayers(in layer: CALayer) -> [CALayer] {
        var out: [CALayer] = []
        if String(describing: type(of: layer)) == "CABackdropLayer" { out.append(layer) }
        for sub in layer.sublayers ?? [] { out += backdropLayers(in: sub) }
        return out
    }
}

/// AppKit re-applies the material recipe in `updateLayer`, so re-strip every pass to keep the
/// mirrored feed sharp and free of the material's fill/tint.
private final class SourceEffectView: NSVisualEffectView {
    override func updateLayer() {
        super.updateLayer()
        strip()
    }

    func strip() {
        guard let root = layer,
              let backdrop = BackdropLoupeView.backdropLayers(in: root).first else { return }
        backdrop.filters = []                                          // strip blur -> sharp feed
        for sibling in backdrop.superlayer?.sublayers ?? [] where sibling !== backdrop {
            sibling.opacity = 0                                        // fill / tone / desktop tint
        }
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
