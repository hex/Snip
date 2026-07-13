// ABOUTME: App-wide observable state: the loaded snippet library and slot lookups.
// ABOUTME: Persists via SnipKit's SnippetStore in Application Support.
import Foundation
import Observation
import SnipKit

/// An app where Snip lets the trigger through instead of opening the ring.
struct IgnoredApp: Codable, Identifiable, Equatable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

@Observable
final class AppModel {
    private static let triggerConfigKey = "triggerConfig"
    private static let ignoredAppsKey = "ignoredApps"

    var library: SnippetLibrary
    var triggerConfig: TriggerConfig {
        didSet { persistTriggerConfig() }
    }
    /// Apps where the trigger is suppressed (e.g. Blender, where the middle button means orbit).
    var ignoredApps: [IgnoredApp] {
        didSet { persistIgnoredApps() }
    }
    var ignoredBundleIDs: Set<String> { Set(ignoredApps.map(\.bundleID)) }
    /// Set by the empty-wedge flow so the library window jumps straight to editing a new snippet.
    /// Transient (not persisted).
    var pendingEditSnippetID: Snippet.ID?
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

        if let data = UserDefaults.standard.data(forKey: Self.ignoredAppsKey),
           let apps = try? JSONDecoder().decode([IgnoredApp].self, from: data) {
            ignoredApps = apps
        } else {
            ignoredApps = []
        }
    }

    private func persistTriggerConfig() {
        guard let data = try? JSONEncoder().encode(triggerConfig) else { return }
        UserDefaults.standard.set(data, forKey: Self.triggerConfigKey)
    }

    private func persistIgnoredApps() {
        guard let data = try? JSONEncoder().encode(ignoredApps) else { return }
        UserDefaults.standard.set(data, forKey: Self.ignoredAppsKey)
    }

    func snippet(inSlot slot: Int) -> Snippet? {
        library.snippets.first { $0.slot == slot }
    }

    func setSlot(_ slot: Int?, for id: Snippet.ID) {
        library.assign(slot: slot, to: id)   // enforces one snippet per slot
        save()
    }

    /// Creates a blank snippet pinned to `slot` and returns its id, for the fire-an-empty-wedge flow.
    @discardableResult
    func createSnippet(inSlot slot: Int?) -> Snippet.ID {
        let snippet = Snippet(label: "", body: "")
        library.snippets.append(snippet)
        if let slot { library.assign(slot: slot, to: snippet.id) }
        save()
        return snippet.id
    }

    func save() {
        try? store.save(library)
    }
}
