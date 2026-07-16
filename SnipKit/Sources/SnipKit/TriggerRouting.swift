// ABOUTME: Per-app trigger resolution: which trigger (if any) opens the ring in front of a given app.
// ABOUTME: Pure lookup logic; the event tap reads it on the hot path, the settings UI edits the rules.
import Foundation

/// What Snip does in front of one specific app: stay out of its way, or open on that app's own
/// trigger instead of the global one.
public enum AppBehavior: Codable, Equatable {
    case suppress
    case trigger(TriggerConfig)
}

/// One app's rule in the settings list: the app's identity plus what Snip does in front of it.
public struct AppRule: Codable, Identifiable, Equatable {
    public var bundleID: String
    public var name: String
    public var behavior: AppBehavior
    public var id: String { bundleID }

    public init(bundleID: String, name: String, behavior: AppBehavior) {
        self.bundleID = bundleID
        self.name = name
        self.behavior = behavior
    }

    /// A stored rule without a behavior is a suppress entry: the list began as suppress-only, so
    /// that's the only thing an entry without the key can mean.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        name = try container.decode(String.self, forKey: .name)
        behavior = try container.decodeIfPresent(AppBehavior.self, forKey: .behavior) ?? .suppress
    }
}

/// Routes the trigger by frontmost app: the global config by default, an app's own trigger where a
/// rule overrides it, or nothing where a rule suppresses the ring.
public struct TriggerRouting: Equatable {
    public var global: TriggerConfig
    public var rules: [String: AppBehavior]   // keyed by bundle identifier

    public init(global: TriggerConfig, rules: [String: AppBehavior] = [:]) {
        self.global = global
        self.rules = rules
    }

    /// The config armed in front of the given app; nil where a rule suppresses the ring.
    public func config(for bundleID: String?) -> TriggerConfig? {
        guard let bundleID, let rule = rules[bundleID] else { return global }
        switch rule {
        case .suppress: return nil
        case .trigger(let config): return config
        }
    }
}
