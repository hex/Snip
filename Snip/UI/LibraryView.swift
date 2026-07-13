// ABOUTME: SwiftUI window to create, edit, delete snippets and arrange them on the ring.
// ABOUTME: Left pane is the ring editor; right pane edits the selected snippet. Mutations persist.
import SwiftUI
import SnipKit

struct LibraryView: View {
    @Bindable var model: AppModel
    @State private var selection: Snippet.ID?
    @FocusState private var labelFocused: Bool

    var body: some View {
        ZStack {
            HUDBackground()
            HSplitView {
                RingEditorView(model: model,
                               selection: $selection,
                               onAddToSlot: addToSlot,
                               onAddUnpinned: addUnpinned,
                               onDelete: deleteSelected)
                    .frame(minWidth: 320, idealWidth: 340, maxWidth: 380)
                detail
            }
        }
        .frame(minWidth: 780, minHeight: 520)
        .preferredColorScheme(.dark)
        .onAppear { consumePendingEdit() }
        .onChange(of: model.pendingEditSnippetID) { _, _ in consumePendingEdit() }
    }

    // MARK: - Detail (editor)

    @ViewBuilder private var detail: some View {
        if let index = selectedIndex {
            editor(for: index)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.insert")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(HUD.textMuted)
            Text("No snippet selected")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HUD.textSecondary)
            Text("Tap a wedge on the ring, or add a snippet with +.")
                .font(.system(size: 12))
                .foregroundStyle(HUD.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                fieldLabel("TEXT")
                TextEditor(text: $model.library.snippets[index].body)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(HUD.textPrimary)
                    .tint(HUD.signal)
                    .padding(10)
                    .frame(minHeight: 200, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10).fill(HUD.socket))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(HUD.hairline, lineWidth: 1))
                tokenShelf(index: index)
            }
        }
        .padding(EdgeInsets(top: 34, leading: 26, bottom: 22, trailing: 26))
        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: model.library) { _, _ in model.save() }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(HUD.textTertiary)
    }

    /// Tokens the snippet expands at paste time, plus the $| caret marker; tapping appends one.
    private func tokenShelf(index: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(["{date}", "{time}", "{clipboard}", "$|"], id: \.self) { token in
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
                .help("Insert \(token)")
            }
            Spacer()
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
