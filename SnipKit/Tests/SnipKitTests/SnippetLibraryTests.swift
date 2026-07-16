// ABOUTME: Tests for SnippetLibrary mutations: empty-draft purging that spares reserved drafts.
import XCTest
@testable import SnipKit

final class SnippetLibraryTests: XCTestCase {
    func testRemoveEmptyDraftsDropsUnkeptBlankDraft() {
        let blank = Snippet(label: "", body: "")
        var lib = SnippetLibrary(schemaVersion: 1, snippets: [blank])
        let changed = lib.removeEmptyDrafts(keeping: [])
        XCTAssertTrue(changed)
        XCTAssertTrue(lib.snippets.isEmpty)
    }

    func testRemoveEmptyDraftsSparesKeptBlankDraft() {
        let kept = Snippet(label: "", body: "")
        let other = Snippet(label: "", body: "")
        var lib = SnippetLibrary(schemaVersion: 1, snippets: [kept, other])
        let changed = lib.removeEmptyDrafts(keeping: [kept.id])
        XCTAssertTrue(changed)                          // `other` removed
        XCTAssertEqual(lib.snippets.map(\.id), [kept.id])
    }

    func testRemoveEmptyDraftsKeepsSnippetsWithContent() {
        let labelled = Snippet(label: "Greeting", body: "")
        let bodied = Snippet(label: "", body: "hi")
        var lib = SnippetLibrary(schemaVersion: 1, snippets: [labelled, bodied])
        let changed = lib.removeEmptyDrafts(keeping: [])
        XCTAssertFalse(changed)
        XCTAssertEqual(lib.snippets.count, 2)
    }
}
