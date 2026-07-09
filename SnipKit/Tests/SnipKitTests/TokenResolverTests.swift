// ABOUTME: Tests for TokenResolver token expansion and $| caret extraction.
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

    func testPlainTextPassesThroughWithZeroCaretOffset() {
        let r = fixedResolver().resolve("Just text")
        XCTAssertEqual(r, ResolvedSnippet(text: "Just text", caretOffsetFromEnd: 0))
    }

    func testCaretMarkerIsRemovedAndOffsetCountsTrailingGraphemes() {
        let r = fixedResolver().resolve("Hi $|,\nThanks")
        XCTAssertEqual(r.text, "Hi ,\nThanks")
        XCTAssertEqual(r.caretOffsetFromEnd, 8)   // ",\nThanks" = 8 graphemes
    }

    func testClipboardTokenUsesInjectedClipboard() {
        let r = fixedResolver(clipboard: "REF-42").resolve("Ref: {clipboard}")
        XCTAssertEqual(r.text, "Ref: REF-42")
    }

    func testMissingClipboardResolvesToEmptyString() {
        let r = fixedResolver(clipboard: nil).resolve("[{clipboard}]")
        XCTAssertEqual(r.text, "[]")
    }

    func testDateTokenResolvesToLocaleMediumString() {
        // Medium style for en_US is "MMM d, y" (CLDR) — stable, no whitespace ambiguity.
        let r = fixedResolver().resolve("Logged {date}.")
        XCTAssertEqual(r.text, "Logged Jul 9, 2026.")
    }

    func testTimeTokenResolvesToShortStyleComponents() {
        // Short style is "h:mm a"; assert components to tolerate ICU's narrow no-break space before AM/PM.
        let r = fixedResolver().resolve("{time}")
        XCTAssertTrue(r.text.contains("3:30"), "expected 3:30 in \\(r.text)")
        XCTAssertTrue(r.text.contains("PM"), "expected PM in \\(r.text)")
    }

    func testCaretOffsetIsGraphemeAwareAcrossEmoji() {
        let r = fixedResolver().resolve("done $|👍")
        XCTAssertEqual(r.text, "done 👍")
        XCTAssertEqual(r.caretOffsetFromEnd, 1)   // one grapheme, not two UTF-16 units
    }
}
