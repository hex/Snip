// ABOUTME: Owns a prewarmed OverlayPanel + NSHostingView; positions, shows, and hides the ring.
// ABOUTME: Prewarming at launch avoids a first-open SwiftUI hitch on the very first trigger.
import AppKit
import SwiftUI
import SnipKit

final class OverlayPanelController {
    private let panel = OverlayPanel()
    private let viewModel = RadialViewModel()
    private let model: AppModel
    private let ringSize = RadialMenuView.ringSize

    init(model: AppModel) {
        self.model = model

        let host = NSHostingView(rootView: RadialMenuView(model: viewModel))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: ringSize, height: ringSize)
        panel.contentView = host
        panel.setContentSize(NSSize(width: ringSize, height: ringSize))

        // Build the SwiftUI graph now, offscreen, so the first real bloom is instant.
        panel.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        panel.orderFrontRegardless()
        panel.orderOut(nil)
    }

    func show(atQuartz quartz: CGPoint) {
        viewModel.labels = (0..<8).map { model.snippet(inSlot: $0)?.label }
        viewModel.selection = .none
        viewModel.isVisible = false

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let center = ScreenGeometry.cocoaPoint(fromQuartz: quartz, primaryScreenHeight: primaryHeight)
        let visible = screenContaining(center)?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let origin = ScreenGeometry.clampedOrigin(forRingSize: ringSize, center: center, in: visible)

        panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y))
        panel.orderFrontRegardless()
        panel.invalidateShadow()   // recompute the circular shadow from the masked content

        // Next runloop tick, so SwiftUI sees a false→true transition and springs.
        DispatchQueue.main.async { self.viewModel.isVisible = true }
    }

    func update(selection: RadialSelection) {
        viewModel.selection = selection
    }

    func hide() {
        viewModel.isVisible = false
        panel.orderOut(nil)
    }

    private func screenContaining(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }
}
