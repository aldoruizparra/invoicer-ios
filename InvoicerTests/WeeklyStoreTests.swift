import Foundation
import InvoicerKit
import SwiftData
import Testing
@testable import Invoicer

/// The weekly tool: typing houses one by one, pasting the email, and building
/// the log the spreadsheet filler gets. All data here is made up.
@MainActor
struct WeeklyStoreTests {
    let container: ModelContainer
    let store: WeeklyStore

    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        store = WeeklyStore(context: container.mainContext)
    }

    func dec(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }

    let pasted = """
    Invoice Date: 10/12//2026
    Work Week:10/04//2026-10/11/2026

    10/07- Acme Homes 100 First St $65

    10/07- Acme Homes  200 Second . $65
    This week, I also cleaned the patio furniture.
    10/08- Beta 300 Third St $50.                          10/08- Gamma Co 400 Fourth Ln $60
    10/09- Echo H. 600 Sixth G $

    Total: $240
    """

    @Test func defaultWeekIsSundayToSaturday() {
        let (s, e) = WeeklyStore.defaultPeriod(containing: Dates.make(2026, 10, 7)!)   // a Wednesday
        #expect(s == Dates.make(2026, 10, 4))
        #expect(e == Dates.make(2026, 10, 10))
        #expect(WeekSheet(start: s, end: e).days.count == 7)
    }

    @Test func typedHousesBecomeTheSpreadsheetLog() {
        let sheet = WeekSheet(start: Dates.make(2026, 10, 4)!, end: Dates.make(2026, 10, 11)!)
        container.mainContext.insert(sheet)
        store.addJob(to: sheet, date: Dates.make(2026, 10, 8)!, client: "Beta", address: "300 Third St", amount: 50)
        store.addJob(to: sheet, date: Dates.make(2026, 10, 7)!, client: " Acme  Homes ", address: "100 First St", amount: 65)
        store.addJob(to: sheet, date: Dates.make(2026, 10, 7)!, client: "Acme Homes", address: "200 Second", amount: nil)
        let log = store.log(for: sheet)
        #expect(log.jobs.map(\.address) == ["100 First St", "200 Second", "300 Third St"])   // by day, then entry order
        #expect(log.jobs[0].client == "Acme Homes")                                        // whitespace tidied
        #expect(log.jobs[1].amount == nil)                                                 // blank stays blank
        #expect(log.parsedTotal == 115)
        #expect(log.filename == "Weekly_Invoice_2026-10-04_to_2026-10-11.xlsx")
    }

    @Test func suggestionsRememberClientsAddressesAndPrices() {
        let sheet = store.currentSheet()
        let d = sheet.start
        store.addJob(to: sheet, date: d, client: "Acme Homes", address: "100 First St", amount: 65)
        store.addJob(to: sheet, date: d, client: "Beta", address: "300 Third St", amount: 50)
        store.addJob(to: sheet, date: d, client: "Acme Homes", address: "200 Second", amount: 70)
        #expect(store.recentClients() == ["Acme Homes", "Beta"])
        #expect(store.addresses(for: "acme homes") == ["200 Second", "100 First St"])
        #expect(store.lastAmount(client: "Acme Homes", address: "100 First St") == 65)
        #expect(store.lastAmount(client: "Acme Homes", address: "New Place") == 70)   // client's latest
        #expect(store.lastAmount(client: "Nobody", address: "") == nil)
    }

    @Test func typedDetailsReachTheLogAndSuggestions() {
        let sheet = store.currentSheet()
        store.addJob(to: sheet, date: sheet.start, client: "Acme Homes", address: "100 First St", amount: 65,
                     jobNumber: " 4521 ", cityState: "Springfield, TX", service: "Move-out clean")
        store.addJob(to: sheet, date: sheet.start, client: "Acme Homes", address: "200 Second", amount: 70)
        let log = store.log(for: sheet)
        #expect(log.jobs[0].jobNumber == "4521")
        #expect(log.jobs[0].cityState == "Springfield, TX")
        #expect(log.jobs[0].service == "Move-out clean")
        #expect(log.jobs[1].service == "")
        #expect(store.recentServices() == ["Move-out clean"])
        // Same house: its own details. New house for the client: the client's latest.
        #expect(store.lastDetails(client: "acme homes", address: "100 first st") == ("Springfield, TX", "Move-out clean"))
        #expect(store.lastDetails(client: "Acme Homes", address: "300 New Rd") == ("Springfield, TX", "Move-out clean"))
        #expect(store.lastDetails(client: "Nobody", address: "") == ("", ""))
        #expect(store.jobs(in: sheet)[0].detail == "100 First St · Springfield, TX · Move-out clean · Job #4521")
    }

    @Test func pasteFillsAnEmptyWeekWithTheEmailsDates() throws {
        let sheet = store.currentSheet()
        let log = try WeeklyStore.parse(pasted, for: sheet)
        let plan = store.plan(log, into: sheet)
        #expect(plan.newPeriod == nil)
        #expect(plan.addCount == 5)
        let target = store.apply(plan, into: sheet)
        #expect(target === sheet)
        #expect(sheet.start == Dates.make(2026, 10, 4))
        #expect(sheet.end == Dates.make(2026, 10, 11))
        #expect(store.jobs(in: sheet).count == 5)
        #expect(sheet.notes == "This week, I also cleaned the patio furniture.")
        #expect(log.statedTotal == log.parsedTotal)

        // Pasting the same email again adds nothing.
        let again = store.plan(try WeeklyStore.parse(pasted, for: sheet), into: sheet)
        #expect(again.duplicates == 5)
        #expect(again.addCount == 0)
    }

    @Test func pasteForAnotherWeekStartsANewWeek() throws {
        let sheet = WeekSheet(start: Dates.make(2026, 10, 11)!, end: Dates.make(2026, 10, 17)!)
        container.mainContext.insert(sheet)
        store.addJob(to: sheet, date: Dates.make(2026, 10, 12)!, client: "Z", address: "1 St", amount: 5)
        let plan = store.plan(try WeeklyStore.parse(pasted, for: sheet), into: sheet)
        #expect(plan.newPeriod?.0 == Dates.make(2026, 10, 4))
        let target = store.apply(plan, into: sheet)
        #expect(target !== sheet)
        #expect(store.jobs(in: target).count == 5)
        #expect(store.jobs(in: sheet).count == 1)
    }

    @Test func typedLinesWithoutWorkWeekUseThisWeeksYear() throws {
        let sheet = WeekSheet(start: Dates.make(2027, 1, 3)!, end: Dates.make(2027, 1, 9)!)
        container.mainContext.insert(sheet)
        let log = try WeeklyStore.parse("01/05- Acme 1 Main St $65\n01/06- Beta 2 Oak $50", for: sheet)
        #expect(log.jobs.map(\.date) == [Dates.make(2027, 1, 5), Dates.make(2027, 1, 6)])
        #expect(log.periodStart == nil)
        store.apply(store.plan(log, into: sheet), into: sheet)
        #expect(sheet.start == Dates.make(2027, 1, 3))   // dates kept
        #expect(store.jobs(in: sheet).count == 2)
    }

    @Test func nextWeekFollowsThePreviousOne() {
        let old = WeekSheet(start: Dates.make(2020, 3, 1)!, end: Dates.make(2020, 3, 7)!)
        container.mainContext.insert(old)
        let next = store.startNextWeek(after: old)
        // An old week rolls forward to the current week, never into the past.
        #expect(next.start == WeeklyStore.defaultPeriod().0)
    }
}
