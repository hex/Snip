// ABOUTME: Observable state the radial view renders: wedge labels, selection, and visibility.
// ABOUTME: Populated by OverlayPanelController; the view never handles input.
import Observation
import SnipKit

@Observable
final class RadialViewModel {
    /// One entry per wedge; nil means an empty, ghosted slot.
    var labels: [String?] = Array(repeating: nil, count: 8)
    var selection: RadialSelection = .none
    /// Drives the bloom spring. Flipped after the panel is ordered front.
    var isVisible: Bool = false
}
