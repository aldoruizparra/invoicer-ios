import Foundation

/// Plain value types shared by the app (SwiftData models convert to/from these)
/// and the renderers. Field names follow the CLI's data.json.

public struct Sender: Equatable, Codable, Sendable {
    public var name = ""
    public var phone = ""
    public var email = ""
    public var street = ""
    public var cityStateZip = ""
    public var payableTo = ""
    public var footerText = Sender.defaultFooter

    public static let defaultFooter = "Materials and labors included in this invoice."

    public init(name: String = "", phone: String = "", email: String = "", street: String = "",
                cityStateZip: String = "", payableTo: String = "",
                footerText: String = Sender.defaultFooter) {
        self.name = name; self.phone = phone; self.email = email; self.street = street
        self.cityStateZip = cityStateZip; self.payableTo = payableTo; self.footerText = footerText
    }
}

public struct ContactInfo: Equatable, Hashable, Codable, Sendable {
    public var attention = ""
    public var attention2 = ""
    public var company = ""
    public var street = ""
    public var cityState = ""
    public var zip = ""

    public init(attention: String = "", attention2: String = "", company: String = "",
                street: String = "", cityState: String = "", zip: String = "") {
        self.attention = attention; self.attention2 = attention2; self.company = company
        self.street = street; self.cityState = cityState; self.zip = zip
    }

    /// Identity used to de-duplicate saved contacts (case/whitespace-insensitive).
    public var key: [String] {
        [attention, attention2, company, street, cityState, zip].map(Strings.norm)
    }

    /// Bill-to lines after "Attention", blank fields skipped.
    public var lines: [String] {
        [attention2, company, street, Strings.cityLine(cityState, zip)].filter { !$0.isEmpty }
    }

    /// "Company - Attn: Name", as in the CLI's pickers.
    public var label: String {
        let parts = [company, attention.isEmpty ? "" : "Attn: " + attention].filter { !$0.isEmpty }
        return parts.isEmpty ? "(blank)" : parts.joined(separator: " - ")
    }

    /// Main name for lists: the company, or the person when there is no company.
    public var title: String { company.isEmpty ? (attention.isEmpty ? "(blank)" : attention) : company }

    /// Secondary line for lists.
    public var subtitle: String {
        var parts: [String] = []
        if !company.isEmpty && !attention.isEmpty { parts.append("Attn: " + attention) }
        let city = Strings.cityLine(cityState, zip)
        if !street.isEmpty { parts.append(street) } else if !city.isEmpty { parts.append(city) }
        return parts.joined(separator: " · ")
    }
}

public struct LineItem: Equatable, Hashable, Codable, Sendable {
    public var description: String
    public var price: Decimal

    public init(description: String, price: Decimal) {
        self.description = description
        self.price = price
    }
}

/// Everything needed to render one invoice.
public struct InvoiceData: Equatable, Sendable {
    public var number: Int
    public var date: Date
    public var billTo: ContactInfo
    /// "street\ncity, state zip" (second line optional), as in the CLI.
    public var jobAddress: String
    public var items: [LineItem]
    public var taxRate: Decimal

    public init(number: Int, date: Date, billTo: ContactInfo, jobAddress: String,
                items: [LineItem], taxRate: Decimal) {
        self.number = number; self.date = date; self.billTo = billTo
        self.jobAddress = jobAddress; self.items = items; self.taxRate = taxRate
    }

    public var totals: Money.Totals { Money.totals(items.map(\.price), rate: taxRate) }

    /// `Invoice_<number>_<YYYY-MM-DD>.pdf`
    public var filename: String { InvoiceData.filename(number: number, date: date) }

    public static func filename(number: Int, date: Date) -> String {
        "Invoice_\(number)_\(Dates.iso(date)).pdf"
    }
}

public enum Strings {
    /// Collapse whitespace and casefold, for duplicate detection.
    public static func norm(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .folding(options: [.caseInsensitive], locale: nil)
    }

    /// "Austin, TX" + "78701" → "Austin, TX 78701"; either part may be blank.
    public static func cityLine(_ cityState: String, _ zip: String) -> String {
        [cityState.trimmingCharacters(in: .whitespaces), zip.trimmingCharacters(in: .whitespaces)]
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Job address stored as "street\ncity line"; shown on one line in lists.
    public static func addressLabel(_ address: String) -> String {
        address.replacingOccurrences(of: "\n", with: ", ")
    }

    /// Build a stored job address from its parts (city line optional).
    public static func jobAddress(street: String, cityState: String, zip: String) -> String {
        [street.trimmingCharacters(in: .whitespaces), cityLine(cityState, zip)]
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

public enum Validate {
    /// Blank, 5 digits, or ZIP+4.
    public static func zip(_ value: String) throws -> String {
        let v = value.trimmingCharacters(in: .whitespaces)
        if !v.isEmpty && v.range(of: #"^\d{5}(-\d{4})?$"#, options: .regularExpression) == nil {
            throw Money.ParseError("ZIP must be 5 digits (or ZIP+4, e.g. 78701-1234), or leave blank")
        }
        return v
    }

    /// "#1044" or "1044" → 1044; must be a positive whole number.
    public static func invoiceNumber(_ value: String) throws -> Int {
        var v = value.trimmingCharacters(in: .whitespaces)
        while v.hasPrefix("#") { v.removeFirst() }
        guard !v.isEmpty, v.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(v), n > 0 else {
            throw Money.ParseError("Invoice number must be a positive whole number")
        }
        return n
    }
}

public enum Dates {
    /// Gregorian calendar in the user's time zone; invoice dates are calendar days.
    public static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    public static func make(_ year: Int, _ month: Int, _ day: Int) -> Date? {
        let comps = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let date = calendar.date(from: comps) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return (back.year == year && back.month == month && back.day == day) ? date : nil
    }

    public static func parts(_ date: Date) -> (year: Int, month: Int, day: Int) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year!, c.month!, c.day!)
    }

    /// 11/07/2026
    public static func mdy(_ date: Date) -> String {
        let p = parts(date)
        return String(format: "%02d/%02d/%04d", p.month, p.day, p.year)
    }

    /// 2026-11-07
    public static func iso(_ date: Date) -> String {
        let p = parts(date)
        return String(format: "%04d-%02d-%02d", p.year, p.month, p.day)
    }

    /// "MM/DD/YYYY" → date, strict like the CLI.
    public static func parseMDY(_ text: String) throws -> Date {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[2].count == 4,
              let m = Int(parts[0]), let d = Int(parts[1]), let y = Int(parts[2]),
              let date = make(y, m, d) else {
            throw Money.ParseError("Use MM/DD/YYYY, e.g. 10/16/2026")
        }
        return date
    }

    /// Noon of the same calendar day, so stored dates never drift across midnight.
    public static func day(_ date: Date) -> Date {
        let p = parts(date)
        return make(p.year, p.month, p.day)!
    }
}
