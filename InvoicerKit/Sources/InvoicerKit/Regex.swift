import Foundation

/// Thin Python-`re`-like wrapper over NSRegularExpression (ICU), which supports
/// the lookbehind the email parser needs.
struct Re: @unchecked Sendable {
    let regex: NSRegularExpression

    init(_ pattern: String, ignoreCase: Bool = false, dotAll: Bool = false) {
        var options: NSRegularExpression.Options = []
        if ignoreCase { options.insert(.caseInsensitive) }
        if dotAll { options.insert(.dotMatchesLineSeparators) }
        regex = try! NSRegularExpression(pattern: pattern, options: options)
    }

    struct Match {
        let result: NSTextCheckingResult
        let text: String

        func group(_ i: Int) -> String? {
            let r = result.range(at: i)
            guard r.location != NSNotFound, let range = Range(r, in: text) else { return nil }
            return String(text[range])
        }

        /// Character offsets (as String.Index) of the whole match.
        var start: String.Index { Range(result.range, in: text)!.lowerBound }
        var end: String.Index { Range(result.range, in: text)!.upperBound }
    }

    /// Like `re.search`.
    func search(_ text: String) -> Match? {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
            .map { Match(result: $0, text: text) }
    }

    /// Like `re.match`: anchored at the start.
    func match(_ text: String) -> Match? {
        regex.firstMatch(in: text, options: .anchored, range: NSRange(text.startIndex..., in: text))
            .map { Match(result: $0, text: text) }
    }

    /// Like `re.finditer`.
    func all(_ text: String) -> [Match] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .map { Match(result: $0, text: text) }
    }

    /// Like `re.sub`; `template` uses `$1` for groups.
    func sub(_ template: String, _ text: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                       withTemplate: template)
    }
}

extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension String {
    /// Python's `" ".join(s.split())`.
    var collapsedWhitespace: String {
        split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Python's `str.rstrip()`.
    var rstripped: String {
        var s = Substring(self)
        while let last = s.last, last.isWhitespace { s.removeLast() }
        return String(s)
    }
}
