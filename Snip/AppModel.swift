// ABOUTME: App-wide observable state: the loaded snippet library and slot lookups.
// ABOUTME: Persists via SnipKit's SnippetStore in Application Support.
import Foundation
import Observation
import SnipKit

@Observable
final class AppModel {
    var library: SnippetLibrary
    private let store: SnippetStore

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Snip", isDirectory: true)
        store = SnippetStore(fileURL: dir.appendingPathComponent("snippets.json"))
        library = (try? store.load()) ?? .empty
    }

    func snippet(inSlot slot: Int) -> Snippet? {
        library.snippets.first { $0.slot == slot }
    }

    func save() {
        try? store.save(library)
    }
}
