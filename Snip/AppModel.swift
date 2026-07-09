// ABOUTME: App-wide observable state: the loaded snippet library and slot lookups.
// ABOUTME: Persists via SnipKit's SnippetStore in Application Support.
import Foundation
import Observation
import SnipKit

@Observable
final class AppModel {
    private static let triggerConfigKey = "triggerConfig"

    var library: SnippetLibrary
    var triggerConfig: TriggerConfig {
        didSet { persistTriggerConfig() }
    }
    private let store: SnippetStore

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Snip", isDirectory: true)
        store = SnippetStore(fileURL: dir.appendingPathComponent("snippets.json"))
        library = (try? store.load()) ?? .empty

        if let data = UserDefaults.standard.data(forKey: Self.triggerConfigKey),
           let config = try? JSONDecoder().decode(TriggerConfig.self, from: data) {
            triggerConfig = config
        } else {
            triggerConfig = TriggerConfig()
        }
    }

    private func persistTriggerConfig() {
        guard let data = try? JSONEncoder().encode(triggerConfig) else { return }
        UserDefaults.standard.set(data, forKey: Self.triggerConfigKey)
    }

    func snippet(inSlot slot: Int) -> Snippet? {
        library.snippets.first { $0.slot == slot }
    }

    func setSlot(_ slot: Int?, for id: Snippet.ID) {
        library.assign(slot: slot, to: id)   // enforces one snippet per slot
        save()
    }

    func save() {
        try? store.save(library)
    }
}
