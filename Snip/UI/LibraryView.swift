// ABOUTME: SwiftUI window to create, edit, delete snippets and arrange them on the ring.
// ABOUTME: Left pane is the ring editor; right pane edits the selected snippet. Mutations persist.
import SwiftUI
import SnipKit

struct LibraryView: View {
    @Bindable var model: AppModel
    @State private var selection: Snippet.ID?
    @FocusState private var labelFocused: Bool

    var body: some View {
        HSplitView {
            RingEditorView(model: model,
                           selection: $selection,
                           onAddToSlot: addToSlot,
                           onAddUnpinned: addUnpinned,
                           onDelete: deleteSelected)
                .frame(minWidth: 320, idealWidth: 340, maxWidth: 380)
            detail
        }
        .onAppear { consumePendingEdit(); purgeEmptyDrafts() }
        .onChange(of: model.pendingEditSnippetID) { _, _ in consumePendingEdit() }
        .onChange(of: selection) { _, _ in purgeEmptyDrafts() }
    }

    /// Tapping an empty wedge creates a blank draft to edit. If it's left with no label and no body,
    /// drop it when the user moves on, so no phantom "Untitled" is saved. The draft being edited (the
    /// selection) and the one reserved by the empty-wedge handoff (pendingEditSnippetID) are kept, so
    /// this never deletes the draft a fire is about to open before the handoff has selected it.
    private func purgeEmptyDrafts() {
        let keep = Set([selection, model.pendingEditSnippetID].compactMap { $0 })
        if model.library.removeEmptyDrafts(keeping: keep) { model.save() }
    }

    // MARK: - Detail (editor)

    @ViewBuilder private var detail: some View {
        if let index = selectedIndex {
            editor(for: index)
        } else {
            emptyState
        }
    }

    /// The panel powered off: a dimmed ghost of the real editor skeleton, so selecting a wedge reads
    /// as the panel powering on rather than a jump cut. Anchored top-left, never centered.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                FieldLabel("NO WEDGE SELECTED")
                Text("Pick a wedge to load it here.")
                    .font(.system(size: 15))
                    .foregroundStyle(HUD.textSecondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    FieldLabel("LABEL")
                    Rectangle().fill(HUD.emphasis).frame(width: 150, height: 1)
                }
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel("TEXT")
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(HUD.hairline, lineWidth: 1)
                        .frame(height: 96)
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 9) {
                                ghostLine(150); ghostLine(96); ghostLine(120)
                            }
                            .padding(12)
                        }
                    HStack(spacing: 6) { ghostChip(52); ghostChip(52); ghostChip(72) }
                }
            }
            .opacity(0.35)

            Spacer(minLength: 0)

            VStack(spacing: 1) {
                legendRow("hand.tap", "Tap a wedge", "edit it")
                legendRow("arrow.up.and.down.and.arrow.left.and.right", "Drag a wedge", "reorder")
                legendRow("arrow.up.forward", "Drag off the ring", "unpin")
            }
        }
        .padding(EdgeInsets(top: 34, leading: 26, bottom: 22, trailing: 26))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func ghostLine(_ width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(HUD.raised).frame(width: width, height: 8)
    }

    private func ghostChip(_ width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6).strokeBorder(HUD.hairline, lineWidth: 1).frame(width: width, height: 20)
    }

    private func legendRow(_ icon: String, _ head: String, _ tail: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(HUD.textTertiary)
                .frame(width: 16)
            Text(head)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HUD.textSecondary)
                .frame(width: 116, alignment: .leading)
            Text(tail)
                .font(.system(size: 12))
                .foregroundStyle(HUD.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 6).fill(HUD.chamber))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HUD.hairline, lineWidth: 1).opacity(0.6))
    }

    private var selectedIndex: Int? {
        guard let selection else { return nil }
        return model.library.snippets.firstIndex { $0.id == selection }
    }

    @ViewBuilder private func editor(for index: Int) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 7) {
                TextField("Label", text: $model.library.snippets[index].label)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(HUD.textPrimary)
                    .focused($labelFocused)
                    .onSubmit { model.save() }
                Rectangle()
                    .fill(labelFocused ? HUD.signal : HUD.hairline)
                    .frame(height: 1)
                    .animation(.easeOut(duration: 0.15), value: labelFocused)
            }

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel("TEXT")
                TextEditor(text: $model.library.snippets[index].body)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(HUD.textPrimary)
                    .tint(HUD.signal)
                    .padding(10)
                    .frame(minHeight: 160, maxHeight: 320)
                    .background(RoundedRectangle(cornerRadius: 10).fill(HUD.field))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(HUD.hairline, lineWidth: 1))
                tokenShelf(index: index)
            }
        }
        .padding(EdgeInsets(top: 34, leading: 26, bottom: 22, trailing: 26))
        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: model.library) { _, _ in model.save() }
    }

    /// Tokens the snippet expands at paste time: value tokens ({date}/{time}/{clipboard}), key-sends
    /// ({enter}/{tab}) that fire a real keystroke, and the $| caret marker. Tapping appends one. The row
    /// scrolls horizontally so the set can grow without crowding the editor.
    private func tokenShelf(index: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(["{date}", "{time}", "{clipboard}", "{enter}", "{tab}", "$|"], id: \.self) { token in
                    Button {
                        model.library.snippets[index].body += token
                        model.save()
                    } label: {
                        Text(token)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(HUD.textSecondary)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(RoundedRectangle(cornerRadius: 6).fill(HUD.chamber))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HUD.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(helpText(for: token))
                }
            }
        }
    }

    private func helpText(for token: String) -> String {
        switch token {
        case "{enter}": return "Send a Return keypress (submits in chat apps)"
        case "{tab}": return "Send a Tab keypress"
        case "$|": return "Place the cursor here after inserting"
        default: return "Insert \(token)"
        }
    }

    // MARK: - Actions

    /// Firing an empty wedge creates a snippet and asks the library to jump straight to editing it.
    private func consumePendingEdit() {
        guard let id = model.pendingEditSnippetID else { return }
        selection = id
        model.pendingEditSnippetID = nil
        // After the editor renders for the new selection, drop the caret into the label.
        DispatchQueue.main.async { labelFocused = true }
    }

    /// Adds a snippet already pinned to an empty ring slot, then jumps to editing it.
    private func addToSlot(_ slot: Int) {
        let id = model.createSnippet(inSlot: slot)
        selection = id
        DispatchQueue.main.async { labelFocused = true }
    }

    private func addUnpinned() {
        let snippet = Snippet(label: "New", body: "")
        model.library.snippets.append(snippet)
        selection = snippet.id
        model.save()
        DispatchQueue.main.async { labelFocused = true }
    }

    private func deleteSelected() {
        guard let id = selection,
              let index = model.library.snippets.firstIndex(where: { $0.id == id }) else { return }
        model.library.snippets.remove(at: index)
        selection = nil
        model.save()
    }
}
