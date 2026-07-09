// ABOUTME: Resolves a snippet template into final text at fire time.
// ABOUTME: Expands {date}/{time}/{clipboard} and extracts the $| caret marker (grapheme-aware).
import Foundation

public struct ResolvedSnippet: Equatable {
    public let text: String
    public let caretOffsetFromEnd: Int
    public init(text: String, caretOffsetFromEnd: Int) {
        self.text = text
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
        // Split at the author's first $| so caret intent survives token expansion.
        let parts = body.components(separatedBy: "$|")
        let hasMarker = parts.count > 1
        let prefix = parts[0]
        let suffix = hasMarker ? parts.dropFirst().joined(separator: "$|") : ""

        let resolvedPrefix = expandTokens(prefix)
        let resolvedSuffix = expandTokens(suffix)
        let text = resolvedPrefix + resolvedSuffix
        let caretOffsetFromEnd = hasMarker ? resolvedSuffix.count : 0
        return ResolvedSnippet(text: text, caretOffsetFromEnd: caretOffsetFromEnd)
    }

    private func expandTokens(_ s: String) -> String {
        s.replacingOccurrences(of: "{date}", with: formatted(dateStyle: .medium, timeStyle: .none))
         .replacingOccurrences(of: "{time}", with: formatted(dateStyle: .none, timeStyle: .short))
         .replacingOccurrences(of: "{clipboard}", with: clipboard() ?? "")
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
