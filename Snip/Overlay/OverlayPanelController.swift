// ABOUTME: Owns a prewarmed OverlayPanel + NSHostingView; positions, shows, and hides the ring.
// ABOUTME: Prewarming at launch avoids a first-open SwiftUI hitch on the very first trigger.
import AppKit
import SwiftUI
import SnipKit

final class OverlayPanelController {
    private let panel = OverlayPanel()
    private let viewModel = RadialViewModel()
    private let model: AppModel
    /// The panel is the canvas, not the ring: the bloom overshoots past the ring's bounds.
    private let canvasSize = RadialMenuView.canvasSize
    /// Bumped on every show so a delayed dismiss never orders out a newer bloom.
    private var generation = 0

    init(model: AppModel) {
        self.model = model

        let host = NSHostingView(rootView: RadialMenuView(model: viewModel))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
        panel.contentView = host
        panel.setContentSize(NSSize(width: canvasSize, height: canvasSize))

        // Build the SwiftUI graph now, offscreen, so the first real bloom is instant.
        panel.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        panel.orderFrontRegardless()
        panel.orderOut(nil)
    }

    func show(atQuartz quartz: CGPoint) {
        generation += 1   // invalidates any pending dismiss from a previous bloom

        viewModel.labels = (0..<8).map { model.snippet(inSlot: $0)?.label }
        viewModel.selection = .none
        viewModel.isDismissing = false
        viewModel.isVisible = false

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let center = ScreenGeometry.cocoaPoint(fromQuartz: quartz, primaryScreenHeight: primaryHeight)
        let origin = ScreenGeometry.centeredOrigin(forSize: canvasSize, center: center)

        panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y))
        panel.reassertSpaceMembership()   // re-evaluate Space membership so first-show-on-fullscreen migrates
        panel.orderFrontRegardless()

        // Next runloop tick, so SwiftUI sees a false→true transition and springs.
        DispatchQueue.main.async { self.viewModel.isVisible = true }
    }

    func update(selection: RadialSelection) {
        viewModel.selection = selection
    }

    func hide() {
        viewModel.isDismissing = true
        viewModel.isVisible = false
        let current = generation
        // Let the dismiss animation play out before the panel leaves the screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            guard current == self.generation else { return }   // a newer bloom already took over
            self.panel.orderOut(nil)
        }
    }
}
