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
        .frame(minWidth: 780, minHeight: 520)
        .onAppear { consumePendingEdit() }
        .onChange(of: model.pendingEditSnippetID) { _, _ in consumePendingEdit() }
    }

    // MARK: - Detail (editor)

    @ViewBuilder private var detail: some View {
        if let index = selectedIndex {
            editor(for: index)
        } else {
            ContentUnavailableView("No snippet selected",
                                   systemImage: "text.insert",
                                   description: Text("Pick one on the left, or add a snippet with +."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var selectedIndex: Int? {
        guard let selection else { return nil }
        return model.library.snippets.firstIndex { $0.id == selection }
    }

    @ViewBuilder private func editor(for index: Int) -> some View {
        let snippet = model.library.snippets[index]

        Form {
            Section {
                TextField("Label", text: $model.library.snippets[index].label)
                    .focused($labelFocused)
                    .onSubmit { model.save() }

                Picker("Ring position", selection: slotBinding(for: snippet.id)) {
                    Text("Unpinned").tag(-1)
                    ForEach(0..<8, id: \.self) { slot in
                        Text(RingEditorView.slotNames[slot]).tag(slot)
                    }
                }
            }

            Section("Text") {
                TextEditor(text: $model.library.snippets[index].body)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 180)
                Text("Tokens: {date} · {time} · {clipboard}      Caret: $|")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420)
        .onChange(of: model.library) { _, _ in model.save() }
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

    /// Maps the picker's Int tag to the optional slot, going through AppModel so the
    /// one-snippet-per-slot rule is enforced in a single place.
    private func slotBinding(for id: Snippet.ID) -> Binding<Int> {
        Binding(
            get: { model.library.snippets.first { $0.id == id }?.slot ?? -1 },
            set: { model.setSlot($0 < 0 ? nil : $0, for: id) })
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
