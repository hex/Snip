// ABOUTME: Resolves a snippet template into an ordered fire plan at fire time.
// ABOUTME: Expands {date}/{time}/{clipboard}, emits {enter}/{tab} as key steps, extracts the $| caret.
import Foundation

/// A synthesized key press a snippet can emit between text runs. Kept free of CoreGraphics so the
/// resolver stays platform-agnostic and testable; the app layer maps these to key codes.
public enum SnippetKey: Equatable {
    case enter   // Return/Enter — sends in chat apps, where a pasted newline would not
    case tab
}

/// One step of a resolved snippet: a run of text to paste, or a key to synthesize. Interleaving lets
/// "line 1{enter}line 2" paste, press Return (send), then paste again.
public enum PasteStep: Equatable {
    case text(String)
    case key(SnippetKey)
}

public struct ResolvedSnippet: Equatable {
    public let steps: [PasteStep]
    /// Graphemes to walk the caret back from the end of the FINAL text run. Non-zero only when the
    /// $| marker lands in that final run with no key after it (arrows can't cross a committed key).
    public let caretOffsetFromEnd: Int
    public init(steps: [PasteStep], caretOffsetFromEnd: Int) {
        self.steps = steps
        self.caretOffsetFromEnd = caretOffsetFromEnd
    }
}

public struct TokenResolver {
    private let now: () -> Date
    private let locale: Locale
    private let timeZone: TimeZone
    private let clipboard: () -> String?

    public init(now: @escaping () -> Date = Date.init,
                locale: Locale = .current,
                timeZone: TimeZone = .current,
                clipboard: @escaping () -> String? = { nil }) {
        self.now = now
        self.locale = locale
        self.timeZone = timeZone
        self.clipboard = clipboard
    }

    public func resolve(_ body: String) -> ResolvedSnippet {
        var steps: [PasteStep] = []
        var run = ""
        var caretActive = false
        var caretSuffixGraphemes = 0
        var caretInvalidated = false

        // Flush the pending text run as a step; empty runs (e.g. between two keys) are dropped, never
        // pasted, so a run of keys doesn't burn empty clipboard writes downstream.
        func flush() {
            if !run.isEmpty { steps.append(.text(run)); run = "" }
        }
        // Substituted token values and literals both land here; they are never re-scanned for tokens,
        // so a clipboard containing "{enter}" is pasted verbatim, not turned into a keystroke.
        func appendText(_ s: String) {
            run += s
            if caretActive && !caretInvalidated { caretSuffixGraphemes += s.count }
        }
        func appendKey(_ key: SnippetKey) {
            flush()
            steps.append(.key(key))
            if caretActive { caretInvalidated = true }
        }

        var rest = Substring(body)
        while let ch = rest.first {
            if rest.hasPrefix("{date}") { appendText(formatted(dateStyle: .medium, timeStyle: .none)); rest = rest.dropFirst("{date}".count); continue }
            if rest.hasPrefix("{time}") { appendText(formatted(dateStyle: .none, timeStyle: .short)); rest = rest.dropFirst("{time}".count); continue }
            if rest.hasPrefix("{clipboard}") { appendText(clipboard() ?? ""); rest = rest.dropFirst("{clipboard}".count); continue }
            if rest.hasPrefix("{enter}") { appendKey(.enter); rest = rest.dropFirst("{enter}".count); continue }
            if rest.hasPrefix("{return}") { appendKey(.enter); rest = rest.dropFirst("{return}".count); continue }
            if rest.hasPrefix("{tab}") { appendKey(.tab); rest = rest.dropFirst("{tab}".count); continue }
            // Only the first $| is the caret marker; later ones fall through as literal text.
            if !caretActive && rest.hasPrefix("$|") { caretActive = true; rest = rest.dropFirst(2); continue }
            appendText(String(ch)); rest = rest.dropFirst()
        }
        flush()

        let caretOffsetFromEnd = (caretActive && !caretInvalidated) ? caretSuffixGraphemes : 0
        return ResolvedSnippet(steps: steps, caretOffsetFromEnd: caretOffsetFromEnd)
    }

    private func formatted(dateStyle: DateFormatter.Style, timeStyle: DateFormatter.Style) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.dateStyle = dateStyle
        f.timeStyle = timeStyle
        return f.string(from: now())
    }
}
