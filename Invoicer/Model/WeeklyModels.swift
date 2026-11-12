import Foundation
import InvoicerKit
import SwiftData

// The weekly contractor sheet: one `WeekSheet` per work week, and one `WorkJob`
// per house cleaned. Jobs point at their week by id (no relationship, which keeps
// CloudKit sync simple). Amount may be blank, like the email's "$".

@Model
final class WeekSheet {
    var sheetID = UUID().uuidString
    var start = Date()
    var end = Date()
    var createdAt = Date()
    /// Free-text notes from an imported email (never written to the spreadsheet).
    var notes = ""
    /// When the client's spreadsheet was last created for this week.
    var exportedAt: Date?

    init(start: Date, end: Date) {
        self.start = Dates.day(start)
        self.end = Dates.day(end)
    }

    var label: String { WeekSheet.label(start, end) }

    static func label(_ start: Date, _ end: Date) -> String {
        let s = Dates.parts(start), e = Dates.parts(end)
        if s.year == e.year { return String(format: "%02d/%02d – %02d/%02d/%04d", s.month, s.day, e.month, e.day, e.year) }
        return "\(Dates.mdy(start)) – \(Dates.mdy(end))"
    }

    /// Every calendar day of the week, for the day picker.
    var days: [Date] {
        var out: [Date] = []
        var d = Dates.day(start)
        let last = Dates.day(end)
        while d <= last && out.count < 31 {
            out.append(d)
            d = Dates.calendar.date(byAdding: .day, value: 1, to: d).map(Dates.day) ?? last.addingTimeInterval(1)
        }
        return out
    }
}

@Model
final class WorkJob {
    var sheetID = ""
    var date = Date()
    var client = ""
    var address = ""
    var amountCents = 0
    var hasAmount = false
    var createdAt = Date()

    init(sheetID: String, date: Date, client: String, address: String, amount: Decimal?, createdAt: Date = Date()) {
        self.sheetID = sheetID
        self.date = Dates.day(date)
        self.client = client
        self.address = address
        self.amount = amount
        self.createdAt = createdAt
    }

    var amount: Decimal? {
        get { hasAmount ? Money.fromCents(amountCents) : nil }
        set {
            hasAmount = newValue != nil
            amountCents = newValue.map(Money.cents) ?? 0
        }
    }
}

/// Rules for the weekly tool, like `Store` is for invoices.
@MainActor
struct WeeklyStore {
    let context: ModelContext

    // MARK: weeks

    func sheets() -> [WeekSheet] {
        (try? context.fetch(FetchDescriptor<WeekSheet>(sortBy: [SortDescriptor(\.start, order: .reverse),
                                                                 SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
    }

    func sheet(id: String) -> WeekSheet? {
        sheets().first { $0.sheetID == id }
    }

    /// Sunday through Saturday of the week containing `day`.
    static func defaultPeriod(containing day: Date = Date()) -> (Date, Date) {
        let cal = Dates.calendar
        let weekday = cal.component(.weekday, from: day)   // 1 = Sunday
        let start = cal.date(byAdding: .day, value: -(weekday - 1), to: Dates.day(day))!
        return (Dates.day(start), Dates.day(cal.date(byAdding: .day, value: 6, to: start)!))
    }

    /// The newest week, creating this week's sheet the first time.
    func currentSheet() -> WeekSheet {
        if let latest = sheets().first { return latest }
        let (s, e) = WeeklyStore.defaultPeriod()
        let sheet = WeekSheet(start: s, end: e)
        context.insert(sheet)
        return sheet
    }

    /// The week after `previous` (same length), or this week if that's later.
    @discardableResult
    func startNextWeek(after previous: WeekSheet?) -> WeekSheet {
        var (s, e) = WeeklyStore.defaultPeriod()
        if let previous {
            let cal = Dates.calendar
            let length = cal.dateComponents([.day], from: previous.start, to: previous.end).day ?? 6
            let next = cal.date(byAdding: .day, value: 1, to: previous.end)!
            if next > s { s = Dates.day(next); e = Dates.day(cal.date(byAdding: .day, value: length, to: next)!) }
        }
        let sheet = WeekSheet(start: s, end: e)
        context.insert(sheet)
        try? context.save()
        return sheet
    }

    // MARK: jobs

    func jobs(in sheet: WeekSheet) -> [WorkJob] {
        let id = sheet.sheetID
        let descriptor = FetchDescriptor<WorkJob>(predicate: #Predicate { $0.sheetID == id },
                                                  sortBy: [SortDescriptor(\.date), SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    func addJob(to sheet: WeekSheet, date: Date, client: String, address: String, amount: Decimal?) -> WorkJob {
        let job = WorkJob(sheetID: sheet.sheetID, date: date, client: clean(client), address: clean(address), amount: amount)
        context.insert(job)
        try? context.save()
        return job
    }

    func delete(_ sheet: WeekSheet) {
        for job in jobs(in: sheet) { context.delete(job) }
        context.delete(sheet)
        try? context.save()
    }

    private func clean(_ s: String) -> String { s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    // MARK: suggestions (most recent first, across all weeks)

    private func allJobs() -> [WorkJob] {
        (try? context.fetch(FetchDescriptor<WorkJob>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
    }

    /// Clients you've used before, most recent first.
    func recentClients(limit: Int = 8) -> [String] {
        unique(allJobs().map(\.client), limit: limit)
    }

    /// Addresses used for this client, most recent first.
    func addresses(for client: String, limit: Int = 8) -> [String] {
        let key = Strings.norm(client)
        return unique(allJobs().filter { Strings.norm($0.client) == key }.map(\.address), limit: limit)
    }

    /// Last amount for this house, else for this client.
    func lastAmount(client: String, address: String) -> Decimal? {
        let c = Strings.norm(client), a = Strings.norm(address)
        let jobs = allJobs().filter { $0.hasAmount && Strings.norm($0.client) == c }
        return (jobs.first { Strings.norm($0.address) == a } ?? jobs.first)?.amount
    }

    private func unique(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for v in values where !v.isEmpty && seen.insert(Strings.norm(v)).inserted {
            out.append(v)
            if out.count == limit { break }
        }
        return out
    }

    // MARK: email / pasted text

    struct ImportPlan {
        let log: WeeklyLog
        /// nil = add to the given sheet; otherwise a new week with these dates.
        let newPeriod: (Date, Date)?
        let duplicates: Int
        var addCount: Int { log.jobs.count - duplicates }
    }

    /// Parse pasted text or an email body. Lines without a "Work Week:" header get
    /// their year from `sheet`'s dates.
    static func parse(_ text: String, for sheet: WeekSheet) throws -> WeeklyLog {
        var log = try EmailLogParser.parse(text)
        if log.periodStart == nil {
            let header = "Work Week: \(Dates.mdy(sheet.start))-\(Dates.mdy(sheet.end))\n"
            log = try EmailLogParser.parse(header + text)
            log.periodStart = nil
            log.periodEnd = nil
        }
        return log
    }

    /// Where an import goes: into `sheet`, or a new week when the text names a
    /// different work week and `sheet` already has houses.
    func plan(_ log: WeeklyLog, into sheet: WeekSheet) -> ImportPlan {
        var newPeriod: (Date, Date)?
        if let s = log.periodStart, let e = log.periodEnd,
           Dates.day(s) != sheet.start || Dates.day(e) != sheet.end, !jobs(in: sheet).isEmpty {
            newPeriod = (s, e)
        }
        let existing = newPeriod == nil ? jobs(in: sheet) : []
        let duplicates = log.jobs.filter { job in
            existing.contains { Dates.day($0.date) == Dates.day(job.date) && Strings.norm($0.client) == Strings.norm(job.client)
                && Strings.norm($0.address) == Strings.norm(job.address) }
        }.count
        return ImportPlan(log: log, newPeriod: newPeriod, duplicates: duplicates)
    }

    /// Apply a plan. Returns the sheet the houses went into.
    @discardableResult
    func apply(_ plan: ImportPlan, into sheet: WeekSheet) -> WeekSheet {
        var target = sheet
        if let (s, e) = plan.newPeriod {
            target = WeekSheet(start: s, end: e)
            context.insert(target)
        } else if let s = plan.log.periodStart, let e = plan.log.periodEnd {
            target.start = Dates.day(s)
            target.end = Dates.day(e)
        }
        let existing = jobs(in: target)
        let base = Date()
        for (i, job) in plan.log.jobs.enumerated() {
            let dup = existing.contains { Dates.day($0.date) == Dates.day(job.date)
                && Strings.norm($0.client) == Strings.norm(job.client) && Strings.norm($0.address) == Strings.norm(job.address) }
            if dup { continue }
            context.insert(WorkJob(sheetID: target.sheetID, date: job.date, client: job.client, address: job.address,
                                   amount: job.amount, createdAt: base.addingTimeInterval(Double(i) / 1000)))
        }
        if !plan.log.notes.isEmpty {
            target.notes = ([target.notes] + plan.log.notes).filter { !$0.isEmpty }.joined(separator: "\n")
        }
        try? context.save()
        return target
    }

    // MARK: export

    /// The week as the log the spreadsheet filler expects.
    func log(for sheet: WeekSheet) -> WeeklyLog {
        var log = WeeklyLog()
        log.periodStart = sheet.start
        log.periodEnd = sheet.end
        log.jobs = jobs(in: sheet).map {
            Job(date: $0.date, client: $0.client, address: $0.address, amount: $0.amount,
                source: "\(Dates.mdy($0.date)) \($0.client) \($0.address)")
        }
        return log
    }
}
