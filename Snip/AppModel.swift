// ABOUTME: App-wide observable state: the loaded snippet library and slot lookups.
// ABOUTME: Persists via SnipKit's SnippetStore in Application Support.
import Foundation
import Observation
import SnipKit

/// Which pane the single Snip window shows. Transient UI state, not persisted.
enum MainTab: Hashable { case snippets, trigger, apps }

@Observable
final class AppModel {
    private static let triggerConfigKey = "triggerConfig"
    private static let appRulesKey = "ignoredApps"   // the key the suppress-only list shipped under

    var library: SnippetLibrary
    var triggerConfig: TriggerConfig {
        didSet { persistTriggerConfig() }
    }
    /// Per-app rules: suppress the trigger (e.g. Blender, where the middle button means orbit) or
    /// open the ring on that app's own trigger instead of the global one.
    var appRules: [AppRule] {
        didSet { persistAppRules() }
    }
    /// The resolved routing the event tap consumes: global trigger plus the per-app rules.
    var triggerRouting: TriggerRouting {
        TriggerRouting(global: triggerConfig,
                       rules: Dictionary(appRules.map { ($0.bundleID, $0.behavior) },
                                         uniquingKeysWith: { first, _ in first }))
    }
    /// Set by the empty-wedge flow so the library window jumps straight to editing a new snippet.
    /// Transient (not persisted).
    var pendingEditSnippetID: Snippet.ID?
    /// The pane shown in the single window; set by the menu items. Transient (not persisted).
    var mainTab: MainTab = .snippets
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

        if let data = UserDefaults.standard.data(forKey: Self.appRulesKey),
           let rules = try? JSONDecoder().decode([AppRule].self, from: data) {
            appRules = rules
        } else {
            appRules = []
        }
    }

    private func persistTriggerConfig() {
        guard let data = try? JSONEncoder().encode(triggerConfig) else { return }
        UserDefaults.standard.set(data, forKey: Self.triggerConfigKey)
    }

    private func persistAppRules() {
        guard let data = try? JSONEncoder().encode(appRules) else { return }
        UserDefaults.standard.set(data, forKey: Self.appRulesKey)
    }

    func snippet(inSlot slot: Int) -> Snippet? {
        library.snippets.first { $0.slot == slot }
    }

    func setSlot(_ slot: Int?, for id: Snippet.ID) {
        library.assign(slot: slot, to: id)   // enforces one snippet per slot
        save()
    }

    /// Drags one ring position onto another, swapping occupants (the ring editor's move gesture).
    func moveSnippet(fromSlot: Int, toSlot: Int) {
        library.moveSnippet(fromSlot: fromSlot, toSlot: toSlot)
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
