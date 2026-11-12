import Foundation

/// Money helpers, ported from the CLI's `money.py`. All math uses `Decimal`;
/// floating point never touches an amount.
public enum Money {
    public struct ParseError: LocalizedError, Equatable, Sendable {
        public let message: String
        public init(_ message: String) { self.message = message }
        public var errorDescription: String? { message }
    }

    static let posix = Locale(identifier: "en_US_POSIX")
    // Plain decimal numbers only: "250", "1250.5", ".5", "5." (no exponents, nan, inf).
    private static let numberPattern = try! NSRegularExpression(
        pattern: #"^[+-]?(\d+\.?\d*|\.\d+)$"#)

    /// `"$1,234.5"` → `1234.50`. Throws on blank, non-numeric or >2 decimal places.
    public static func parse(_ text: String) throws -> Decimal {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        if cleaned.isEmpty { throw ParseError("Enter an amount, e.g. 250 or 1,250.00") }
        guard matches(numberPattern, cleaned), let value = Decimal(string: cleaned, locale: posix) else {
            throw ParseError("'\(text)' is not a valid amount")
        }
        if let dot = cleaned.firstIndex(of: "."), cleaned[cleaned.index(after: dot)...].count > 2 {
            throw ParseError("Use at most 2 decimal places")
        }
        return value
    }

    /// `"8.25"` or `"8.25%"` → `8.25`. Must be between 0 and 100.
    public static func parseRate(_ text: String) throws -> Decimal {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasSuffix("%") { cleaned.removeLast() }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard matches(numberPattern, cleaned), let rate = Decimal(string: cleaned, locale: posix) else {
            throw ParseError("'\(text)' is not a valid tax rate")
        }
        if rate < 0 || rate > 100 { throw ParseError("Tax rate must be between 0 and 100") }
        return rate
    }

    /// Round to cents, half-up (away from zero on .5), like Python's ROUND_HALF_UP.
    public static func roundCents(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }

    public struct Totals: Equatable, Sendable {
        public let subtotal: Decimal
        public let tax: Decimal
        public let total: Decimal
    }

    /// Subtotal, tax (rounded to cents, half-up) and total.
    public static func totals(_ prices: [Decimal], rate: Decimal) -> Totals {
        let subtotal = roundCents(prices.reduce(Decimal(0), +))
        let tax = roundCents(subtotal * rate / 100)
        return Totals(subtotal: subtotal, tax: tax, total: subtotal + tax)
    }

    /// `1234.5` → `"$1,234.50"`; negatives → `"-$1,234.50"`.
    public static func format(_ value: Decimal) -> String {
        roundCents(value).formatted(
            .currency(code: "USD").locale(Locale(identifier: "en_US")).precision(.fractionLength(2)))
    }

    /// `8.250` → `"8.25"`, `10` → `"10"`.
    public static func formatRate(_ rate: Decimal) -> String {
        NSDecimalNumber(decimal: rate).description(withLocale: posix)
    }

    /// Cents ↔ Decimal, for storage.
    public static func cents(_ value: Decimal) -> Int {
        NSDecimalNumber(decimal: roundCents(value) * 100).intValue
    }

    public static func fromCents(_ cents: Int) -> Decimal {
        Decimal(cents) / 100
    }

    /// Text for an editable price field: `250` → `"250.00"`.
    public static func plain(_ value: Decimal) -> String {
        let rounded = roundCents(value)
        let s = NSDecimalNumber(decimal: rounded).description(withLocale: posix)
        guard let dot = s.firstIndex(of: ".") else { return s + ".00" }
        let decimals = s[s.index(after: dot)...].count
        return decimals == 1 ? s + "0" : s
    }
}

func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
    regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
}
