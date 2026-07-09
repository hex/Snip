// ABOUTME: Tests for the Snippet and SnippetLibrary domain models.
// ABOUTME: Verifies JSON round-tripping and the empty-library defaults.
import XCTest
@testable import SnipKit

final class SnippetModelTests: XCTestCase {
    func testSnippetRoundTripsThroughJSON() throws {
        let snippet = Snippet(id: UUID(), label: "SLA", caption: "reply", body: "Hi $|,", slot: 5)
        let data = try JSONEncoder().encode(snippet)
        let decoded = try JSONDecoder().decode(Snippet.self, from: data)
        XCTAssertEqual(decoded, snippet)
    }

    func testEmptyLibraryHasCurrentSchemaVersionAndNoSnippets() {
        XCTAssertEqual(SnippetLibrary.empty.schemaVersion, SnippetLibrary.currentSchemaVersion)
        XCTAssertTrue(SnippetLibrary.empty.snippets.isEmpty)
    }
}
