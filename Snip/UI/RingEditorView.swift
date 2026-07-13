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
            RingBoard(model: model, selection: $selection, onAddToSlot: onAddToSlot)
                .padding(.top, 34)   // clear the floating traffic lights
                .padding(.bottom, 16)
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
        .dropDestination(for: String.self) { items, _ in
            // A wedge dragged here unpins its snippet; an already-unpinned drag is a no-op.
            guard let payload = items.first, let drag = RingDrag(payload),
                  case .slot(let from) = drag, let snippet = model.snippet(inSlot: from) else { return false }
            model.setSlot(nil, for: snippet.id)
            return true
        }
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
            .draggable(RingDrag.snippet(snippet.id).transferString)
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

/// A static render of the live radial menu: the same glass ring, spokes, accent-filled selected
/// wedge, wedge labels, and glossy hub the overlay draws, minus the bloom and the magnifying loupe.
/// Each wedge carries a circular tap/drag target at its label so you can edit, add, move, and swap.
private struct RingBoard: View {
    @Bindable var model: AppModel
    @Binding var selection: Snippet.ID?
    var onAddToSlot: (Int) -> Void

    static let size: CGFloat = 272
    static let hubFraction: CGFloat = 0.30
    private var hubSize: CGFloat { Self.size * Self.hubFraction }
    private let labelRadius: CGFloat = 90
    private let accent = Color(nsColor: .controlAccentColor)

    var body: some View {
        ZStack {
            glassRing

            if let index = selectedIndex {
                WedgeShape(index: index, wedgeCount: 8, innerRadiusFraction: Self.hubFraction)
                    .fill(accent.opacity(0.50))
            }

            SpokesShape(wedgeCount: 8, innerRadiusFraction: Self.hubFraction)
                .stroke(.white.opacity(0.16), lineWidth: 1)

            Circle().strokeBorder(
                LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0.10)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1)

            hub

            ForEach(0..<8, id: \.self) { wedgePetal($0) }
        }
        .frame(width: Self.size, height: Self.size)
    }

    private var glassRing: some View {
        ZStack {
            RingShape(holeFraction: Self.hubFraction)
                .fill(.black.opacity(0.26), style: FillStyle(eoFill: true))
                .blur(radius: 13)
                .offset(y: 6)

            VisualEffectView(diameter: Self.size, holeFraction: Self.hubFraction)

            RingShape(holeFraction: Self.hubFraction)
                .fill(.black.opacity(0.16), style: FillStyle(eoFill: true))

            RingShape(holeFraction: Self.hubFraction)
                .fill(LinearGradient(colors: [.white.opacity(0.12), .clear],
                                     startPoint: .top, endPoint: .center),
                      style: FillStyle(eoFill: true))
        }
    }

    /// The dark glossy hub sphere, using the same dressing as the overlay (no magnifying loupe here).
    private var hub: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(hex: 0x2B2F38), Color(hex: 0x121419)],
                                         center: UnitPoint(x: 0.4, y: 0.34),
                                         startRadius: 0, endRadius: hubSize * 0.62))
            GlassHubDressing(hubSize: hubSize)
        }
        .frame(width: hubSize, height: hubSize)
    }

    private var selectedIndex: Int? {
        guard let selection,
              let snippet = model.library.snippets.first(where: { $0.id == selection }) else { return nil }
        return snippet.slot
    }

    /// The wedge's label (or a + when empty) plus a circular tap/drag target, placed at the wedge
    /// centroid exactly where the live menu draws its label.
    @ViewBuilder private func wedgePetal(_ index: Int) -> some View {
        let angle = Double(index) * .pi / 4   // clockwise from up
        let snippet = model.snippet(inSlot: index)
        let isSelected = snippet != nil && snippet?.id == selection
        let text = snippet.map { $0.label.isEmpty ? "Untitled" : $0.label }

        let petal = ZStack {
            Circle().fill(Color.white.opacity(0.001)).frame(width: 68, height: 68)
            Text(text ?? "+")
                .font(.system(size: 12, weight: text == nil ? .regular : .semibold))
                .foregroundStyle(labelColor(isSelected: isSelected, isEmpty: text == nil))
                .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                .scaleEffect(isSelected ? 1.12 : 1.0)
                .lineLimit(1)
                .frame(width: 76)
        }
        .contentShape(Circle())
        .onTapGesture {
            if let snippet { selection = snippet.id } else { onAddToSlot(index) }
        }
        .dropDestination(for: String.self) { items, _ in drop(items.first, onWedge: index) }
        .offset(x: labelRadius * sin(angle), y: -labelRadius * cos(angle))

        if snippet != nil {
            petal.draggable(RingDrag.slot(index).transferString)
        } else {
            petal
        }
    }

    private func drop(_ payload: String?, onWedge index: Int) -> Bool {
        guard let payload, let drag = RingDrag(payload) else { return false }
        switch drag {
        case .slot(let from): model.moveSnippet(fromSlot: from, toSlot: index)
        case .snippet(let id): model.setSlot(index, for: id)
        }
        return true
    }

    private func labelColor(isSelected: Bool, isEmpty: Bool) -> Color {
        if isSelected { return .white }
        if isEmpty { return .white.opacity(0.34) }
        return .white.opacity(0.94)
    }
}

/// The ring editor's drag payload, carried as a String so one `dropDestination(for: String.self)`
/// can tell a moved wedge from a dragged-in unpinned snippet.
private enum RingDrag {
    case slot(Int)
    case snippet(Snippet.ID)

    var transferString: String {
        switch self {
        case .slot(let index): return "slot:\(index)"
        case .snippet(let id): return "snip:\(id.uuidString)"
        }
    }

    init?(_ string: String) {
        if string.hasPrefix("slot:"), let index = Int(string.dropFirst(5)) {
            self = .slot(index)
        } else if string.hasPrefix("snip:"), let id = UUID(uuidString: String(string.dropFirst(5))) {
            self = .snippet(id)
        } else {
            return nil
        }
    }
}
