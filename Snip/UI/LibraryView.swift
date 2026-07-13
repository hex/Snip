// ABOUTME: SwiftUI window to create, edit, delete snippets and pin them to ring slots 0 through 7.
// ABOUTME: Mutations write through AppModel and persist immediately.
import SwiftUI
import SnipKit

struct LibraryView: View {
    @Bindable var model: AppModel
    @State private var selection: Snippet.ID?
    @FocusState private var labelFocused: Bool

    /// Wedge 0 points up; indices increase clockwise. Naming them beats "Slot 3".
    private static let slotNames = [
        "Top", "Top right", "Right", "Bottom right",
        "Bottom", "Bottom left", "Left", "Top left",
    ]

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(model.library.snippets) { snippet in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snippet.label.isEmpty ? "Untitled" : snippet.label)
                            .font(.headline)
                        Text(snippet.slot.map { Self.slotNames[$0] } ?? "Unpinned")
                            .font(.caption)
                            .foregroundStyle(snippet.slot == nil ? .tertiary : .secondary)
                    }
                    .tag(snippet.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .toolbar {
                Button(action: addSnippet) {
                    Label("New snippet", systemImage: "plus")
                }
            }
        } detail: {
            if let index = selectedIndex {
                editor(for: index)
            } else {
                ContentUnavailableView("No snippet selected",
                                       systemImage: "text.insert",
                                       description: Text("Pick one on the left, or add a new snippet."))
            }
        }
        .frame(minWidth: 680, minHeight: 440)
        .onAppear { consumePendingEdit() }
        .onChange(of: model.pendingEditSnippetID) { _, _ in consumePendingEdit() }
    }

    /// Firing an empty wedge creates a snippet and asks the library to jump straight to editing it.
    private func consumePendingEdit() {
        guard let id = model.pendingEditSnippetID else { return }
        selection = id
        model.pendingEditSnippetID = nil
        // After the editor renders for the new selection, drop the caret into the label.
        DispatchQueue.main.async { labelFocused = true }
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
                        Text(Self.slotNames[slot]).tag(slot)
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

            Section {
                Button("Delete snippet", role: .destructive) { deleteSnippet(index) }
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.library) { _, _ in model.save() }
    }

    /// Maps the picker's Int tag to the optional slot, going through AppModel so the
    /// one-snippet-per-slot rule is enforced in a single place.
    private func slotBinding(for id: Snippet.ID) -> Binding<Int> {
        Binding(
            get: { model.library.snippets.first { $0.id == id }?.slot ?? -1 },
            set: { model.setSlot($0 < 0 ? nil : $0, for: id) })
    }

    private func addSnippet() {
        let snippet = Snippet(label: "New", body: "")
        model.library.snippets.append(snippet)
        selection = snippet.id
        model.save()
    }

    private func deleteSnippet(_ index: Int) {
        let removed = model.library.snippets.remove(at: index)
        if selection == removed.id { selection = nil }
        model.save()
    }
}
