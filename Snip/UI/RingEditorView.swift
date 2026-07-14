// ABOUTME: The Library's left pane: a static render of the ACTUAL radial menu (shared shapes + hub),
// ABOUTME: so it matches the live overlay exactly. Tap a wedge to edit/add; drag a wedge to move/swap.
import SwiftUI
import SnipKit

struct RingEditorView: View {
    @Bindable var model: AppModel
    @Binding var selection: Snippet.ID?
    /// Create a new snippet pinned to an empty wedge, then select and focus it.
    var onAddToSlot: (Int) -> Void
    /// Create a new unpinned snippet, then select and focus it.
    var onAddUnpinned: () -> Void
    /// Delete the current selection.
    var onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            RingBoard(model: model, selection: $selection, onAddToSlot: onAddToSlot)
            Spacer(minLength: 12)
            Divider().overlay(HUD.hairline)
            tray
            Divider().overlay(HUD.hairline)
            bottomBar
        }
    }

    // MARK: - Unpinned tray

    private var unpinnedSnippets: [Snippet] {
        model.library.snippets.filter { $0.slot == nil }
    }

    private var tray: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("UNPINNED")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(HUD.textTertiary)
                .padding(.horizontal, 14)

            if unpinnedSnippets.isEmpty {
                Text("Drag a wedge here to unpin it.")
                    .font(.system(size: 11))
                    .foregroundStyle(HUD.textMuted)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(unpinnedSnippets) { snippet in trayChip(snippet) }
                    }
                    .padding(.horizontal, 14)
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func trayChip(_ snippet: Snippet) -> some View {
        let isSelected = snippet.id == selection
        return Text(snippet.label.isEmpty ? "Untitled" : snippet.label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isSelected ? HUD.textPrimary : HUD.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(HUD.chamber))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? HUD.signal : HUD.hairline, lineWidth: isSelected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture { selection = snippet.id }
            .draggable(snippet.id.uuidString)   // drop onto a wedge to pin it there
    }

    // MARK: - Add / remove

    private var bottomBar: some View {
        HStack(spacing: 6) {
            barButton("plus", help: "New snippet", action: onAddUnpinned)
            barButton("minus", help: "Delete selected snippet", action: onDelete)
                .disabled(selection == nil)
                .opacity(selection == nil ? 0.4 : 1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func barButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HUD.textSecondary)
                .frame(width: 26, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(HUD.chamber))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HUD.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// A live render of the radial menu: the same glass ring, spokes, wedge labels, and glossy hub the
/// overlay draws. A wedge is dragged in real time (its label follows the cursor and the target wedge
/// lights up); releasing snaps it to the nearest wedge and swaps, or unpins it if flung off the ring.
private struct RingBoard: View {
    @Bindable var model: AppModel
    @Binding var selection: Snippet.ID?
    var onAddToSlot: (Int) -> Void

    static let size: CGFloat = 272
    static let hubFraction: CGFloat = 0.30
    private var hubSize: CGFloat { Self.size * Self.hubFraction }
    private var center: CGPoint { CGPoint(x: Self.size / 2, y: Self.size / 2) }
    private var outerRadius: CGFloat { Self.size / 2 }
    private var hubRadius: CGFloat { outerRadius * Self.hubFraction }
    private let labelRadius: CGFloat = 90

    /// The dial the menu bar shows, kept once and engraved faintly onto the hub as a maker's mark.
    private static let brandMark = menuBarDialImage()

    /// The wedge currently being dragged and where its label sits (ring coordinate space).
    @State private var drag: DragState?
    private struct DragState { let slot: Int; var location: CGPoint }

    var body: some View {
        ZStack {
            glassRing
            calibrationBezel
            SpokesShape(wedgeCount: 8, innerRadiusFraction: Self.hubFraction)
                .stroke(.white.opacity(0.14), lineWidth: 1)
            litBearing
            Circle().strokeBorder(
                LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0.10)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
            hub
            makersMark
            ForEach(0..<8, id: \.self) { wedgePetal($0) }
            if let drag { dragGhost(drag) }
        }
        .frame(width: Self.size, height: Self.size)
        .animation(.easeOut(duration: 0.12), value: litWedgeIndex)
        .coordinateSpace(.named("ring"))
        .dropDestination(for: String.self) { items, location in
            // A tray chip dropped onto the ring pins it to the wedge under the drop.
            guard let first = items.first, let id = UUID(uuidString: first),
                  let target = wedge(at: location) else { return false }
            model.setSlot(target, for: id)
            return true
        }
    }

    /// The wedge to light: the live drag target while dragging, otherwise the current selection.
    private var litWedgeIndex: Int? {
        if let drag { return wedge(at: drag.location) }
        return selectedIndex
    }

    /// The lit bearing: the active wedge reads as backlit from behind rather than filled. A low azure
    /// wash, its two boundary spokes lit, and a bright inner-arc rim with a hotter core and a soft glow.
    @ViewBuilder private var litBearing: some View {
        if let lit = litWedgeIndex {
            ZStack {
                WedgeShape(index: lit, wedgeCount: 8, innerRadiusFraction: Self.hubFraction)
                    .fill(HUD.signal.opacity(0.12))
                WedgeBoundarySpokes(index: lit, wedgeCount: 8, innerRadiusFraction: Self.hubFraction)
                    .stroke(HUD.signal.opacity(0.5), lineWidth: 1)
                WedgeInnerArc(index: lit, wedgeCount: 8, innerRadiusFraction: Self.hubFraction)
                    .stroke(HUD.signal.opacity(0.35), lineWidth: 4).blur(radius: 4)
                WedgeInnerArc(index: lit, wedgeCount: 8, innerRadiusFraction: Self.hubFraction)
                    .stroke(HUD.signal, lineWidth: 1.5)
                WedgeInnerArc(index: lit, wedgeCount: 8, innerRadiusFraction: Self.hubFraction)
                    .stroke(HUD.signalCore, lineWidth: 0.75)
            }
        }
    }

    private var glassRing: some View {
        ZStack {
            // The dial's cast shadow: the one true shadow the ring is allowed.
            RingShape(holeFraction: Self.hubFraction)
                .fill(.black.opacity(0.30), style: FillStyle(eoFill: true))
                .blur(radius: 14)
                .offset(y: 7)

            // A brushed-metal descent: the ridge crown at the top falling to the machined plate.
            RingShape(holeFraction: Self.hubFraction)
                .fill(LinearGradient(colors: [HUD.ridge, HUD.chamber],
                                     startPoint: .top, endPoint: .bottom),
                      style: FillStyle(eoFill: true))

            // A crisp specular bevel along the top edge, like light on a milled crown.
            RingShape(holeFraction: Self.hubFraction)
                .fill(LinearGradient(colors: [HUD.bevel, .clear],
                                     startPoint: .top, endPoint: .center),
                      style: FillStyle(eoFill: true))
        }
    }

    /// Engraved graduations milled into the bezel: major ticks on the eight wedge boundaries, finer
    /// minor ticks between. The signature that turns a glass menu into a calibrated instrument.
    private var calibrationBezel: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = min(size.width, size.height) / 2
            for i in 0..<32 {   // minor graduations every 11.25 degrees
                let a = -Double.pi / 2 + Double(i) * (2 * Double.pi / 32)
                var p = Path()
                p.move(to: CGPoint(x: c.x + (outer - 5) * cos(a), y: c.y + (outer - 5) * sin(a)))
                p.addLine(to: CGPoint(x: c.x + (outer - 1) * cos(a), y: c.y + (outer - 1) * sin(a)))
                ctx.stroke(p, with: .color(.white.opacity(0.08)), lineWidth: 1)
            }
            for i in 0..<8 {    // major ticks on the wedge boundaries
                let a = -Double.pi / 2 + (Double(i) + 0.5) * (2 * Double.pi / 8)
                var p = Path()
                p.move(to: CGPoint(x: c.x + (outer - 8) * cos(a), y: c.y + (outer - 8) * sin(a)))
                p.addLine(to: CGPoint(x: c.x + (outer - 1) * cos(a), y: c.y + (outer - 1) * sin(a)))
                ctx.stroke(p, with: .color(.white.opacity(0.18)), lineWidth: 1)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .allowsHitTesting(false)
    }

    /// The dark glossy hub sphere, using the same dressing as the overlay (no magnifying loupe here).
    private var hub: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(hex: 0x2B313C), Color(hex: 0x0F1116)],
                                         center: UnitPoint(x: 0.4, y: 0.34),
                                         startRadius: 0, endRadius: hubSize * 0.62))
            GlassHubDressing(hubSize: hubSize)
        }
        .frame(width: hubSize, height: hubSize)
    }

    /// The maker's mark: the dial engraved faintly into the hub boss, centered on the instrument.
    private var makersMark: some View {
        Image(nsImage: Self.brandMark)
            .renderingMode(.template)
            .resizable()
            .frame(width: 30, height: 30)
            .foregroundStyle(HUD.textSecondary)
            .opacity(0.4)
            .allowsHitTesting(false)
    }

    private var selectedIndex: Int? {
        guard let selection,
              let snippet = model.library.snippets.first(where: { $0.id == selection }) else { return nil }
        return snippet.slot
    }

    /// The wedge's label (or a + when empty) plus a circular tap/drag target at the wedge centroid.
    /// While this wedge is being dragged its label is hidden here and drawn as the moving ghost.
    private func wedgePetal(_ index: Int) -> some View {
        let angle = Double(index) * .pi / 4   // clockwise from up
        let snippet = model.snippet(inSlot: index)
        let isSelected = snippet != nil && snippet?.id == selection
        let text = snippet.map { $0.label.isEmpty ? "Untitled" : $0.label }
        let isDragging = drag?.slot == index

        return ZStack {
            Circle().fill(Color.white.opacity(0.001)).frame(width: 68, height: 68)
            if !isDragging {
                Text(text ?? "+")
                    .font(.system(size: 12, weight: text == nil ? .regular : .semibold))
                    .foregroundStyle(labelColor(isSelected: isSelected, isEmpty: text == nil))
                    .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                    .shadow(color: HUD.signal.opacity(isSelected ? 0.55 : 0), radius: 8)
                    .scaleEffect(isSelected ? 1.06 : 1.0)
                    .animation(.easeOut(duration: 0.12), value: isSelected)
                    .lineLimit(1)
                    .frame(width: 76)
            }
        }
        .contentShape(Circle())
        .offset(x: labelRadius * sin(angle), y: -labelRadius * cos(angle))
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("ring"))
                .onChanged { value in
                    guard snippet != nil, moved(value) else { return }
                    drag = DragState(slot: index, location: value.location)
                }
                .onEnded { value in
                    if !moved(value) {
                        if let snippet { selection = snippet.id } else { onAddToSlot(index) }
                    } else if let snippet {
                        commitDrag(from: index, to: value.location, snippet: snippet)
                    }
                    drag = nil
                }
        )
    }

    /// The label of the wedge being dragged, following the cursor above everything else.
    private func dragGhost(_ drag: DragState) -> some View {
        let snippet = model.snippet(inSlot: drag.slot)
        return Text(snippet.map { $0.label.isEmpty ? "Untitled" : $0.label } ?? "")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            .scaleEffect(1.15)
            .position(drag.location)
            .allowsHitTesting(false)
    }

    private func moved(_ value: DragGesture.Value) -> Bool {
        hypot(value.translation.width, value.translation.height) > 6
    }

    private func commitDrag(from: Int, to location: CGPoint, snippet: Snippet) {
        if hypot(location.x - center.x, location.y - center.y) > outerRadius * 1.12 {
            model.setSlot(nil, for: snippet.id)   // flung off the ring: unpin
        } else if let target = wedge(at: location), target != from {
            model.moveSnippet(fromSlot: from, toSlot: target)
        }
        // released in the hub or back on itself: no change
    }

    /// The wedge index under a ring-space point, or nil when the point is in the hub or off the ring.
    private func wedge(at location: CGPoint) -> Int? {
        let dx = location.x - center.x, dy = location.y - center.y
        let distance = hypot(dx, dy)
        guard distance > hubRadius, distance <= outerRadius * 1.12 else { return nil }
        var a = atan2(dx, -dy)   // 0 = up, increasing clockwise
        if a < 0 { a += 2 * .pi }
        return Int((a / (2 * .pi / 8)).rounded()) % 8
    }

    private func labelColor(isSelected: Bool, isEmpty: Bool) -> Color {
        if isSelected { return .white }
        if isEmpty { return .white.opacity(0.34) }
        return .white.opacity(0.94)
    }
}
