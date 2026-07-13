// ABOUTME: The Library's left pane: a visual 8-slot ring mirroring the radial menu's geometry.
// ABOUTME: Tap a slot to edit/add; drag a slot onto another to move/swap; drag to Unpinned to unpin.
import SwiftUI
import SnipKit

struct RingEditorView: View {
    @Bindable var model: AppModel
    @Binding var selection: Snippet.ID?
    /// Create a new snippet pinned to an empty slot, then select and focus it.
    var onAddToSlot: (Int) -> Void
    /// Create a new unpinned snippet, then select and focus it.
    var onAddUnpinned: () -> Void
    /// Delete the current selection.
    var onDelete: () -> Void

    /// Wedge 0 points up; indices increase clockwise. Named positions beat "Slot 3".
    static let slotNames = [
        "Top", "Top right", "Right", "Bottom right",
        "Bottom", "Bottom left", "Left", "Top left",
    ]

    var body: some View {
        VStack(spacing: 0) {
            ring
                .padding(.vertical, 10)
            Divider()
            unpinned
            Divider()
            bottomBar
        }
    }

    // MARK: - Ring

    /// A fixed-size square keeps the geometry predictable (GeometryReader has no intrinsic size, so
    /// pairing it with aspectRatio is unreliable). The left pane is sized to hold this comfortably.
    private var ring: some View {
        let size: CGFloat = 300
        let radius: CGFloat = 108
        let center = CGPoint(x: size / 2, y: size / 2)
        return ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                .frame(width: radius * 2, height: radius * 2)
                .position(center)

            ForEach(0..<8, id: \.self) { slot in
                let angle = Double(slot) / 8 * 2 * .pi   // 0 at top, clockwise
                slotCell(slot)
                    .position(x: center.x + radius * sin(angle),
                              y: center.y - radius * cos(angle))
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private func slotCell(_ slot: Int) -> some View {
        let snippet = model.snippet(inSlot: slot)
        let cell = RingSlotCell(name: Self.slotNames[slot],
                                snippet: snippet,
                                isSelected: snippet != nil && snippet?.id == selection)
            .contentShape(Circle())
            .onTapGesture {
                if let snippet { selection = snippet.id } else { onAddToSlot(slot) }
            }
            .dropDestination(for: String.self) { items, _ in
                drop(items.first, onSlot: slot)
            }

        if snippet != nil {
            cell.draggable(RingDrag.slot(slot).transferString)
        } else {
            cell
        }
    }

    private func drop(_ payload: String?, onSlot slot: Int) -> Bool {
        guard let payload, let drag = RingDrag(payload) else { return false }
        switch drag {
        case .slot(let from): model.moveSnippet(fromSlot: from, toSlot: slot)
        case .snippet(let id): model.setSlot(slot, for: id)
        }
        return true
    }

    // MARK: - Unpinned

    private var unpinnedSnippets: [Snippet] {
        model.library.snippets.filter { $0.slot == nil }
    }

    private var unpinned: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Unpinned")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 6)

            List(selection: $selection) {
                ForEach(unpinnedSnippets) { snippet in
                    Text(snippet.label.isEmpty ? "Untitled" : snippet.label)
                        .tag(snippet.id)
                        .draggable(RingDrag.snippet(snippet.id).transferString)
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 90)
        }
        .dropDestination(for: String.self) { items, _ in
            // A ring slot dragged here unpins its snippet; an already-unpinned drag is a no-op.
            guard let payload = items.first, let drag = RingDrag(payload),
                  case .slot(let from) = drag, let snippet = model.snippet(inSlot: from) else { return false }
            model.setSlot(nil, for: snippet.id)
            return true
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button(action: onAddUnpinned) {
                Image(systemName: "plus").frame(width: 24, height: 20)
            }
            .help("New snippet")

            Button(action: onDelete) {
                Image(systemName: "minus").frame(width: 24, height: 20)
            }
            .disabled(selection == nil)
            .help("Delete selected snippet")

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
}

/// One position on the ring: shows the pinned snippet's label, or a + when empty.
private struct RingSlotCell: View {
    let name: String
    let snippet: Snippet?
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(snippet == nil ? Color.secondary.opacity(0.08) : Color.accentColor.opacity(0.18))
                Circle()
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                                  lineWidth: isSelected ? 2 : 1)
                if let snippet {
                    Text(snippet.label.isEmpty ? "Untitled" : snippet.label)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .padding(.horizontal, 5)
                } else {
                    Image(systemName: "plus").foregroundStyle(.secondary)
                }
            }
            .frame(width: 60, height: 60)

            Text(name)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(width: 74)
    }
}

/// The ring editor's drag payload, carried as a String so one `dropDestination(for: String.self)`
/// can tell a moved ring position from a dragged-in unpinned snippet.
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
