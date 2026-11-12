#if DEBUG
import Foundation
import InvoicerKit
import SwiftData

/// Debug-only launch arguments for screenshots and manual testing:
///   -demoData YES          in-memory store seeded with the prototype's fake data
///   -demoSetup YES         in-memory store with no profile (shows onboarding)
///   -openScreen <name>     newInvoice | repeat | review | saved | settings | weekly | preview | item
/// Never touches the real store.
@MainActor
enum DebugLaunch {
    static var arguments: UserDefaults { .standard }

    static func demoContainer() -> ModelContainer? {
        let seed = arguments.bool(forKey: "demoData")
        let blank = arguments.bool(forKey: "demoSetup")
        guard seed || blank else { return nil }
        let schema = Schema(Schema1.models)
        let container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        if seed { seedPrototypeData(container.mainContext) }
        return container
    }

    static var openScreen: String? { arguments.string(forKey: "openScreen") }

    /// The prototype's sample data (made up).
    static func seedPrototypeData(_ context: ModelContext) {
        let biz = Business()
        biz.name = "Jane Doe Cleaning"; biz.phone = "(555) 555-0100"; biz.email = "jane@example.com"
        biz.street = "123 Example Street"; biz.cityStateZip = "Springfield, TX 75000"; biz.payableTo = "Jane Doe Cleaning"
        biz.defaultTaxRate = "8.25"
        biz.lastInvoiceNumber = 1043
        biz.contractorName = "Jane Doe"
        context.insert(biz)

        let harbor = ContactInfo(attention: "John Sample", company: "Example Property Mgmt",
                                 street: "1 Demo Way", cityState: "Springfield, TX", zip: "75001")
        let maria = ContactInfo(attention: "Mary Placeholder", street: "77 Sample Dr", cityState: "Springfield, TX")
        let lake = ContactInfo(attention: "Board Treasurer", company: "Test Lake HOA",
                               street: "300 Lake Example Ave", cityState: "Springfield, TX", zip: "75002")
        let addresses = ["14 Demo Ave\nSpringfield, TX", "77 Sample Dr\nSpringfield, TX", "300 Lake Example Ave\nSpringfield, TX"]
        let now = Date()
        for (i, c) in [harbor, maria, lake].enumerated() { context.insert(Contact(c, lastUsed: now.addingTimeInterval(-Double(i) * 60))) }
        for (i, a) in addresses.enumerated() { context.insert(JobAddress(a, lastUsed: now.addingTimeInterval(-Double(i) * 60))) }
        let items: [(String, Decimal)] = [("Weekly lawn mowing & edging", 65), ("Hedge trimming", 120),
                                          ("Leaf removal & haul-away", 95), ("Gutter cleaning", 180),
                                          ("Sprinkler head replacement", 25)]
        for (i, item) in items.enumerated() {
            context.insert(SavedItem(description: item.0, price: item.1, lastUsed: now.addingTimeInterval(-Double(i) * 60)))
        }
        let rate = Decimal(string: "8.25")!
        let history: [(Int, (Int, Int), ContactInfo, String, [LineItem])] = [
            (1040, (10, 10), harbor, addresses[0], [LineItem(description: items[0].0, price: 65), LineItem(description: items[1].0, price: 120)]),
            (1041, (10, 17), lake, addresses[2], [LineItem(description: items[3].0, price: 180), LineItem(description: items[2].0, price: 95)]),
            (1042, (10, 24), maria, addresses[1], [LineItem(description: items[0].0, price: 65), LineItem(description: items[4].0, price: 25)]),
            (1043, (10, 31), harbor, addresses[0], [LineItem(description: items[0].0, price: 65), LineItem(description: items[1].0, price: 120), LineItem(description: items[2].0, price: 95)]),
        ]
        for (i, h) in history.enumerated() {
            let inv = Invoice(InvoiceData(number: h.0, date: Dates.make(2026, h.1.0, h.1.1)!, billTo: h.2,
                                          jobAddress: h.3, items: h.4, taxRate: rate))
            inv.createdAt = now.addingTimeInterval(Double(i - 10) * 3600)
            context.insert(inv)
        }
        // A week in progress on the Weekly tab (made-up houses).
        let (start, end) = (Dates.make(2026, 10, 4)!, Dates.make(2026, 10, 10)!)
        let sheet = WeekSheet(start: start, end: end)
        sheet.createdAt = now
        context.insert(sheet)
        let jobs: [(Int, String, String, Decimal?)] = [
            (6, "Mary Placeholder", "77 Sample Dr", 65), (7, "Example Property Mgmt", "14 Demo Ave", 65),
            (7, "Example Property Mgmt", "22 Demo Ct", 65), (7, "Sample Residence", "512 Test Blvd", nil),
            (9, "Test Lake HOA", "300 Lake Example Ave", 180), (10, "Doe Family", "90 Example Rd", 120),
        ]
        for (i, j) in jobs.enumerated() {
            context.insert(WorkJob(sheetID: sheet.sheetID, date: Dates.make(2026, 10, j.0)!, client: j.1, address: j.2,
                                   amount: j.3, createdAt: now.addingTimeInterval(Double(i)),
                                   jobNumber: i % 2 == 0 ? String(4500 + i) : "", cityState: "Springfield, TX",
                                   service: i == 4 ? "Deep clean" : "Standard clean"))
        }
        try? context.save()
    }

    /// A made-up work-log email for the weekly screen.
    static let sampleEmail = """
    Subject: Invoice
    Content-Type: text/plain; charset=utf-8

    From: Jane Doe
    123 Example Street
    Springfield, TX 75000
    Invoice Date: 10/12/2026
    Work Week: 10/05/2026-10/11/2026
    10/06- Mary Placeholder 77 Sample Dr $65
    10/07- Example Property Mgmt 14 Demo Ave $65   10/07- Sample Residence 512 Test Blvd $
    10/09- Test Lake HOA 300 Lake Example Ave $180
    10/10- Doe Family 90 Example Rd $120
    Also cleaned the patio furniture at the lake house.
    Total: $495
    """
}
#endif
