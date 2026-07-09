// ABOUTME: Loads and atomically saves the SnippetLibrary as JSON on disk.
// ABOUTME: Returns an empty library when absent and migrates older schema versions forward.
import Foundation

public final class SnippetStore {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> SnippetLibrary {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }
        let data = try Data(contentsOf: fileURL)
        var library = try JSONDecoder().decode(SnippetLibrary.self, from: data)
        library = migrate(library)
        return library
    }

    public func save(_ library: SnippetLibrary) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(library)
        try data.write(to: fileURL, options: .atomic)
    }

    private func migrate(_ library: SnippetLibrary) -> SnippetLibrary {
        // No historical versions yet; bump schemaVersion so re-saves record current.
        var migrated = library
        migrated.schemaVersion = SnippetLibrary.currentSchemaVersion
        return migrated
    }
}
