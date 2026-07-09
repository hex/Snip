// ABOUTME: Tests the one-snippet-per-slot invariant when pinning snippets to ring positions.
// ABOUTME: A wedge is a physical position, so assigning a taken slot must evict the occupant.
import XCTest
@testable import SnipKit

final class SlotAssignmentTests: XCTestCase {
    private func library() -> (SnippetLibrary, Snippet, Snippet) {
        let first = Snippet(label: "SIG", body: "Alex", slot: 3)
        let second = Snippet(label: "HI", body: "Hi", slot: nil)
        return (SnippetLibrary(schemaVersion: 1, snippets: [first, second]), first, second)
    }

    func testAssigningATakenSlotEvictsThePreviousOccupant() {
        var (lib, first, second) = library()
        lib.assign(slot: 3, to: second.id)
        XCTAssertNil(lib.snippets.first { $0.id == first.id }?.slot)
        XCTAssertEqual(lib.snippets.first { $0.id == second.id }?.slot, 3)
    }

    func testAssigningNilUnpinsWithoutTouchingOthers() {
        var (lib, first, second) = library()
        lib.assign(slot: 5, to: second.id)
        lib.assign(slot: nil, to: first.id)
        XCTAssertNil(lib.snippets.first { $0.id == first.id }?.slot)
        XCTAssertEqual(lib.snippets.first { $0.id == second.id }?.slot, 5)
    }

    func testReassigningTheSameSnippetToItsOwnSlotIsIdempotent() {
        var (lib, first, _) = library()
        lib.assign(slot: 3, to: first.id)
        XCTAssertEqual(lib.snippets.first { $0.id == first.id }?.slot, 3)
        XCTAssertEqual(lib.snippets.filter { $0.slot == 3 }.count, 1)
    }

    func testAssigningToAnUnknownIdChangesNothing() {
        var (lib, _, _) = library()
        let before = lib
        lib.assign(slot: 7, to: UUID())
        XCTAssertEqual(lib, before)
    }
}
