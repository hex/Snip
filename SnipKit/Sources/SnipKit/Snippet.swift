// ABOUTME: Codable domain models for a snippet and the persisted snippet library.
// ABOUTME: schemaVersion enables forward-compatible migration in SnippetStore.
import Foundation

public struct Snippet: Codable, Identifiable, Equatable {
    public let id: UUID
    public var label: String
    public var caption: String?
    public var body: String
    public var slot: Int?

    public init(id: UUID = UUID(), label: String, caption: String? = nil, body: String, slot: Int? = nil) {
        self.id = id
        self.label = label
        self.caption = caption
        self.body = body
        self.slot = slot
    }
}

public struct SnippetLibrary: Codable, Equatable {
    public static let currentSchemaVersion = 1
    public static let empty = SnippetLibrary(schemaVersion: currentSchemaVersion, snippets: [])

    public var schemaVersion: Int
    public var snippets: [Snippet]

    public init(schemaVersion: Int, snippets: [Snippet]) {
        self.schemaVersion = schemaVersion
        self.snippets = snippets
    }

    /// A ring wedge is a physical position, so a slot holds at most one snippet.
    /// Pinning to a taken slot evicts its previous occupant rather than shadowing it.
    public mutating func assign(slot: Int?, to id: Snippet.ID) {
        guard let target = snippets.firstIndex(where: { $0.id == id }) else { return }
        if let slot {
            for index in snippets.indices where index != target && snippets[index].slot == slot {
                snippets[index].slot = nil
            }
        }
        snippets[target].slot = slot
    }

    /// Moves the snippet at `fromSlot` to `toSlot`, swapping with the occupant of `toSlot` if any.
    /// A no-op when the slots match or `fromSlot` is empty. This is the ring editor's drag gesture.
    public mutating func moveSnippet(fromSlot: Int, toSlot: Int) {
        guard fromSlot != toSlot,
              let source = snippets.firstIndex(where: { $0.slot == fromSlot }) else { return }
        let dest = snippets.firstIndex { $0.slot == toSlot }
        snippets[source].slot = toSlot
        if let dest, dest != source { snippets[dest].slot = fromSlot }
    }

    /// Drops unlabelled, empty drafts (blank label AND blank body) except those in `ids`, which are
    /// reserved for editing (the current selection and the pending empty-wedge handoff). Returns
    /// whether anything was removed, so the caller can skip a save when the library is unchanged.
    @discardableResult
    public mutating func removeEmptyDrafts(keeping ids: Set<Snippet.ID>) -> Bool {
        let before = snippets.count
        snippets.removeAll { !ids.contains($0.id) && $0.label.isEmpty && $0.body.isEmpty }
        return snippets.count != before
    }
}
