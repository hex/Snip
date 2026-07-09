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
}
