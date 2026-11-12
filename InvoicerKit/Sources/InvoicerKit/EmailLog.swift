import Foundation

/// Parse a weekly work-log email body into jobs. Port of the CLI's `email_log.py`.
///
/// Expected body, loosely (typos like `10/12//2026` and missing amounts are tolerated):
///
///     From: Contractor Name
///     123 Street
///     City, ST 12345
///     Invoice Date: 10/12/2026
///     Work Week: 10/04/2026-10/11/2026
///     10/07- Client Name 123 Some St $65
///     10/08- Other Client 9 Main St $50   10/08- Third 4 Elm $60
///     A free-text note line
///     Total: $175
public struct Job: Equatable, Identifiable, Sendable {
    public let id = UUID()
    public var date: Date
    public var client: String
    public var address: String
    /// nil when the email left the amount blank.
    public var amount: Decimal?
    /// The original text, for messages.
    public var source: String
    // Columns the email doesn't have; filled when houses are typed in.
    public var jobNumber: String
    public var cityState: String
    public var service: String

    public init(date: Date, client: String, address: String, amount: Decimal?, source: String,
                jobNumber: String = "", cityState: String = "", service: String = "") {
        self.date = date; self.client = client; self.address = address
        self.amount = amount; self.source = source
        self.jobNumber = jobNumber; self.cityState = cityState; self.service = service
    }

    public static func == (a: Job, b: Job) -> Bool {
        a.date == b.date && a.client == b.client && a.address == b.address
            && a.amount == b.amount && a.source == b.source
            && a.jobNumber == b.jobNumber && a.cityState == b.cityState && a.service == b.service
    }
}

public struct WeeklyLog: Equatable, Sendable {
    public var invoiceDate: Date?
    public var periodStart: Date?
    public var periodEnd: Date?
    public var senderLines: [String] = []
    public var jobs: [Job] = []
    public var notes: [String] = []
    public var statedTotal: Decimal?

    public init() {}

    /// Sum of the amounts that are filled in.
    public var parsedTotal: Decimal {
        jobs.compactMap(\.amount).reduce(Decimal(0), +)
    }

    public var missingCount: Int { jobs.filter { $0.amount == nil }.count }

    /// `Weekly_Invoice_<start>_to_<end>.xlsx`
    public var filename: String {
        let start = periodStart.map(Dates.iso) ?? "unknown"
        let end = periodEnd.map(Dates.iso) ?? "unknown"
        return "Weekly_Invoice_\(start)_to_\(end).xlsx"
    }

    /// Contractor fields guessed from the email's "From:" block (name, street, city line).
    public var suggestedContractor: Contractor {
        var c = Contractor()
        if senderLines.count > 0 { c.name = senderLines[0] }
        if senderLines.count > 1 { c.street = senderLines[1] }
        if senderLines.count > 2 { c.cityStateZip = senderLines[2] }
        return c
    }
}

public struct EmailLogError: LocalizedError, Equatable, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum EmailLogParser {
    static let datePattern = #"\d{1,2}\s*/+\s*\d{1,2}\s*/+\s*\d{2,4}"#
    static let invoiceDateRe = Re(#"Invoice\s*Date\s*:?\s*("# + datePattern + ")", ignoreCase: true)
    static let workWeekRe = Re(#"Work\s*Week\s*:?\s*("# + datePattern + #")\s*(?:-|–|to)\s*("# + datePattern + ")",
                               ignoreCase: true)
    static let totalRe = Re(#"^\s*Total\s*:?\s*\$?\s*([\d,]+(?:\.\d{1,2})?)"#, ignoreCase: true)
    /// "10/07-" at the start of a job entry; several entries may share one line.
    static let entryRe = Re(#"(?<![\d/])(\d{1,2})/(\d{1,2})\s*-\s*"#)
    static let amountRe = Re(#"\$\s*([\d,]*(?:\.\d{1,2})?)"#)
    static let headerRe = Re(#"^\s*(To|From|Invoice\s*Date|Work\s*Week)\s*:"#, ignoreCase: true)
    static let fromRe = Re(#"^\s*From\s*:\s*(.*)$"#, ignoreCase: true)
    static let clientRe = Re(#"^(.*?)\s*(\d.*)$"#)
    static let trailingDotRe = Re(#"\s+\.$"#)
    static let dateSplitRe = Re(#"\s*/+\s*"#)

    /// `"10/12//2026"` or `"10/12/26"` → 2026-10-12.
    public static func parseDate(_ text: String) throws -> Date {
        let parts = dateSplitRe.sub("/", text.trimmed).split(separator: "/").compactMap { Int($0) }
        guard parts.count == 3 else { throw EmailLogError(message: "Bad date '\(text)'") }
        var (month, day, year) = (parts[0], parts[1], parts[2])
        if year < 100 { year += 2000 }
        guard let date = Dates.make(year, month, day) else {
            throw EmailLogError(message: "Bad date '\(text)'")
        }
        return date
    }

    /// Year for a "MM/DD" entry, from the work week (handles Dec → Jan weeks).
    static func inferYear(month: Int, day: Int, start: Date?, end: Date?) -> Int {
        guard let start else { return Dates.parts(Date()).year }
        let startYear = Dates.parts(start).year
        if let end, Dates.parts(end).year > startYear,
           let candidate = Dates.make(startYear, month, day), candidate < start {
            return Dates.parts(end).year
        }
        return startYear
    }

    static func clean(_ text: String) -> String {
        trailingDotRe.sub("", text.collapsedWhitespace).trimmed
    }

    static func parseEntry(month: Int, day: Int, segment: String, log: WeeklyLog) throws -> Job {
        let amounts = amountRe.all(segment)
        var desc = segment
        var amount: Decimal?
        if let last = amounts.last {
            desc = String(segment[..<last.start])
            var raw = last.group(1) ?? ""
            while raw.hasSuffix(".") { raw.removeLast() }
            if !raw.replacingOccurrences(of: ",", with: "").isEmpty {
                amount = try Money.parse(raw)
            }
        }
        desc = clean(desc)
        // Client name runs until the first token that starts with a digit (house number).
        var client = desc, address = ""
        if let m = clientRe.match(desc) {
            client = clean(m.group(1) ?? "")
            address = clean(m.group(2) ?? "")
        }
        let year = inferYear(month: month, day: day, start: log.periodStart, end: log.periodEnd)
        guard let date = Dates.make(year, month, day) else {
            throw EmailLogError(message: "Bad job date \(month)/\(day)")
        }
        return Job(date: date, client: client, address: address, amount: amount,
                   source: String(format: "%02d/%02d- ", month, day) + clean(segment))
    }

    public static func parse(_ text: String) throws -> WeeklyLog {
        var log = WeeklyLog()
        // Python's splitlines(): "\r\n" is one break (a single Character in Swift).
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
            .map { String($0).rstripped }

        for line in lines {
            if let m = invoiceDateRe.search(line) { log.invoiceDate = try parseDate(m.group(1)!) }
            if let m = workWeekRe.search(line) {
                log.periodStart = try parseDate(m.group(1)!)
                log.periodEnd = try parseDate(m.group(2)!)
            }
        }

        var inFrom = false, afterWeek = false
        for line in lines {
            let stripped = line.trimmed
            if stripped.isEmpty { inFrom = false; continue }
            if let m = fromRe.match(line) {
                inFrom = true
                let value = (m.group(1) ?? "").trimmed
                if !value.isEmpty { log.senderLines.append(value) }
                continue
            }
            if headerRe.match(line) != nil {
                inFrom = false
                afterWeek = afterWeek || workWeekRe.search(line) != nil
                continue
            }
            if let m = totalRe.match(line) {
                log.statedTotal = try Money.parse(m.group(1)!)
                inFrom = false
                continue
            }
            let starts = entryRe.all(line)
            if !starts.isEmpty {
                inFrom = false
                for (i, s) in starts.enumerated() {
                    let end = i + 1 < starts.count ? starts[i + 1].start : line.endIndex
                    let segment = String(line[s.end..<end])
                    log.jobs.append(try parseEntry(month: Int(s.group(1)!)!, day: Int(s.group(2)!)!,
                                                   segment: segment, log: log))
                }
            } else if inFrom {
                log.senderLines.append(stripped)
            } else if afterWeek {
                log.notes.append(stripped)
            }
        }
        return log
    }
}

/// Contractor block written into the weekly template (cells C9–C14).
public struct Contractor: Equatable, Codable, Sendable {
    public var name = ""
    public var street = ""
    public var address2 = ""
    public var cityStateZip = ""
    public var email = ""
    public var phone = ""

    public init(name: String = "", street: String = "", address2: String = "",
                cityStateZip: String = "", email: String = "", phone: String = "") {
        self.name = name; self.street = street; self.address2 = address2
        self.cityStateZip = cityStateZip; self.email = email; self.phone = phone
    }
}
