// ABOUTME: Tests for SnippetStore JSON persistence.
// ABOUTME: Covers missing-file default, save/load round-trip, and directory creation.
import XCTest
@testable import SnipKit

final class SnippetStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("snippets.json")
    }

    func testLoadReturnsEmptyWhenFileMissing() throws {
        let store = SnippetStore(fileURL: tempURL())
        XCTAssertEqual(try store.load(), SnippetLibrary.empty)
    }

    func testSaveThenLoadRoundTrips() throws {
        let url = tempURL()
        let store = SnippetStore(fileURL: url)
        let lib = SnippetLibrary(schemaVersion: 1, snippets: [Snippet(label: "SIG", body: "Alex", slot: 0)])
        try store.save(lib)
        XCTAssertEqual(try store.load(), lib)
    }

    func testSaveCreatesIntermediateDirectories() throws {
        let url = tempURL()   // includes a non-existent parent directory
        let store = SnippetStore(fileURL: url)
        try store.save(.empty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
