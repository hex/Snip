// ABOUTME: Tests for TokenResolver: token expansion, key-send steps, and $| caret extraction.
// ABOUTME: Uses a fixed clock/locale/timezone; {time} is asserted by components to survive ICU whitespace.
import XCTest
@testable import SnipKit

final class TokenResolverTests: XCTestCase {
    // 2026-07-09 15:30:00 UTC (epoch verified via `date`), en_US, UTC.
    private func fixedResolver(clipboard: String? = nil) -> TokenResolver {
        let date = Date(timeIntervalSince1970: 1_783_611_000)
        return TokenResolver(now: { date }, locale: Locale(identifier: "en_US"),
                             timeZone: TimeZone(identifier: "UTC")!, clipboard: { clipboard })
    }

    /// The concatenation of the text steps, ignoring key steps — for assertions that don't care about
    /// run boundaries (date/time formatting).
    private func text(of resolved: ResolvedSnippet) -> String {
        resolved.steps.reduce(into: "") { if case let .text(t) = $1 { $0 += t } }
    }

    // MARK: - Text and value tokens

    func testPlainTextIsASingleTextStep() {
        let r = fixedResolver().resolve("Just text")
        XCTAssertEqual(r, ResolvedSnippet(steps: [.text("Just text")], caretOffsetFromEnd: 0))
    }

    func testClipboardTokenUsesInjectedClipboard() {
        let r = fixedResolver(clipboard: "REF-42").resolve("Ref: {clipboard}")
        XCTAssertEqual(r.steps, [.text("Ref: REF-42")])
    }

    func testMissingClipboardResolvesToEmptyString() {
        let r = fixedResolver(clipboard: nil).resolve("[{clipboard}]")
        XCTAssertEqual(r.steps, [.text("[]")])
    }

    func testDateTokenResolvesToLocaleMediumString() {
        // Medium style for en_US is "MMM d, y" (CLDR) — stable, no whitespace ambiguity.
        let r = fixedResolver().resolve("Logged {date}.")
        XCTAssertEqual(r.steps, [.text("Logged Jul 9, 2026.")])
    }

    func testTimeTokenResolvesToShortStyleComponents() {
        // Short style is "h:mm a"; assert components to tolerate ICU's narrow no-break space before AM/PM.
        let r = fixedResolver().resolve("{time}")
        XCTAssertEqual(r.steps.count, 1)
        XCTAssertTrue(text(of: r).contains("3:30"), "expected 3:30 in \(text(of: r))")
        XCTAssertTrue(text(of: r).contains("PM"), "expected PM in \(text(of: r))")
    }

    // MARK: - Key-send tokens

    func testEnterTokenBecomesTrailingKeyStep() {
        let r = fixedResolver().resolve("My text{enter}")
        XCTAssertEqual(r.steps, [.text("My text"), .key(.enter)])
    }

    func testReturnTokenAliasesEnter() {
        let r = fixedResolver().resolve("a{return}b")
        XCTAssertEqual(r.steps, [.text("a"), .key(.enter), .text("b")])
    }

    func testTabTokenBecomesKeyStep() {
        let r = fixedResolver().resolve("a{tab}b")
        XCTAssertEqual(r.steps, [.text("a"), .key(.tab), .text("b")])
    }

    func testConsecutiveKeysProduceNoEmptyTextSteps() {
        let r = fixedResolver().resolve("{enter}{enter}")
        XCTAssertEqual(r.steps, [.key(.enter), .key(.enter)])
    }

    /// A clipboard value that contains a literal "{enter}" must NOT synthesize a keystroke — the
    /// template is parsed first, substituted values are never re-scanned for tokens.
    func testClipboardContentIsNotRescannedForKeyTokens() {
        let r = fixedResolver(clipboard: "x{enter}y").resolve("{clipboard}")
        XCTAssertEqual(r.steps, [.text("x{enter}y")])
    }

    // MARK: - Caret marker

    func testCaretMarkerOffsetCountsTrailingGraphemes() {
        let r = fixedResolver().resolve("Hi $|,\nThanks")
        XCTAssertEqual(r.steps, [.text("Hi ,\nThanks")])
        XCTAssertEqual(r.caretOffsetFromEnd, 8)   // ",\nThanks" = 8 graphemes
    }

    func testCaretOffsetIsGraphemeAwareAcrossEmoji() {
        let r = fixedResolver().resolve("done $|👍")
        XCTAssertEqual(r.steps, [.text("done 👍")])
        XCTAssertEqual(r.caretOffsetFromEnd, 1)   // one grapheme, not two UTF-16 units
    }

    /// A caret marker in the final text run (no key after it) is honored, counting into that run.
    func testCaretInFinalRunAfterKeyIsHonored() {
        let r = fixedResolver().resolve("a{enter}b$|c")
        XCTAssertEqual(r.steps, [.text("a"), .key(.enter), .text("bc")])
        XCTAssertEqual(r.caretOffsetFromEnd, 1)   // "c"
    }

    /// A caret marker followed by a key can't be honored (arrows can't cross a committed Return), so
    /// the offset is dropped.
    func testCaretBeforeKeyIsIgnored() {
        let r = fixedResolver().resolve("a$|b{enter}c")
        XCTAssertEqual(r.steps, [.text("ab"), .key(.enter), .text("c")])
        XCTAssertEqual(r.caretOffsetFromEnd, 0)
    }
}
