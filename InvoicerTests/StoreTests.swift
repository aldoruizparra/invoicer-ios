import Foundation
import InvoicerKit
import SwiftData
import Testing
@testable import Invoicer

/// Port of tests/test_invoicer.py FlowTests against the SwiftData store:
/// numbering, cancel doesn't consume a number, MRU lists, duplicates.
@MainActor
struct StoreTests {
    let container: ModelContainer
    let store: Store
    let files: FileStore
    let outDir: URL

    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        store = Store(context: container.mainContext)
        outDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        files = FileStore(syncEnabled: false, localRoot: outDir)
        let biz = store.business()
        biz.name = "Test Sender"
        biz.phone = "555-0100"
    }

    func dec(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }

    func sampleInvoice(number: Int) -> InvoiceData {
        InvoiceData(number: number, date: Dates.make(2026, 10, 16)!,
                    billTo: ContactInfo(attention: "John Smith", company: "Acme LLC", street: "1 Main St",
                                        cityState: "Dallas, TX", zip: "75201"),
                    jobAddress: "456 Oak Ave\nPlano, TX",
                    items: [LineItem(description: "Deep clean", price: 250),
                            LineItem(description: "Extra", price: dec("1000.50"))],
                    taxRate: dec("8.25"))
    }

    @Test func newInvoiceConfirm() throws {
        let biz = store.business()
        let draft = InvoiceDraft(business: biz)
        #expect(draft.numberText == "1")
        try store.finalize(sampleInvoice(number: 1), files: files)
        #expect(biz.lastInvoiceNumber == 1)
        #expect(biz.nextInvoiceNumber == 2)
        #expect(files.exists("Invoice_1_2026-10-16.pdf"))
        let contacts = try container.mainContext.fetch(FetchDescriptor<Contact>())
        #expect(contacts.map(\.company) == ["Acme LLC"])
        #expect(contacts.first?.zip == "75201")
        #expect(try container.mainContext.fetch(FetchDescriptor<JobAddress>()).map(\.text) == ["456 Oak Ave\nPlano, TX"])
        let items = try container.mainContext.fetch(FetchDescriptor<SavedItem>(sortBy: [SortDescriptor(\.lastUsed, order: .reverse)]))
        #expect(items.map(\.itemDescription) == ["Deep clean", "Extra"])   // first line most recent
        #expect(items[1].lastPrice == dec("1000.50"))
    }

    @Test func cancelDoesNotIncrement() throws {
        let biz = store.business()
        // A draft is built and abandoned: nothing is recorded, no file is written.
        let draft = InvoiceDraft(business: biz)
        draft.contact = ContactInfo(attention: "A")
        draft.address = "1 St"
        draft.lines = [LineItem(description: "X", price: 5)]
        #expect(draft.data != nil)
        #expect(biz.lastInvoiceNumber == 0)
        #expect(InvoiceDraft(business: biz).numberText == "1")
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Invoice>()) == 0)
        let written = (try? FileManager.default.contentsOfDirectory(atPath: files.outputDirectory.path)) ?? []
        #expect(written.isEmpty)
    }

    @Test func rejectsDuplicateNumber() throws {
        try store.finalize(sampleInvoice(number: 5), files: files)
        #expect(throws: Store.StoreError.duplicateNumber(5)) { try store.finalize(sampleInvoice(number: 5), files: files) }
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Invoice>()) == 1)
        // Counter keeps the highest number used; a lower free number is still allowed.
        try store.finalize(sampleInvoice(number: 3), files: files)
        #expect(store.business().lastInvoiceNumber == 5)
    }

    @Test func repeatAndMRU() throws {
        try store.finalize(sampleInvoice(number: 1), files: files)
        var repeated = try #require(store.repeatDraft(today: Dates.make(2026, 11, 7)!))
        #expect(repeated.number == 2)
        #expect(repeated.date == Dates.make(2026, 11, 7))
        #expect(repeated.billTo.company == "Acme LLC")
        repeated.items[1].price = 75
        try store.finalize(repeated, files: files)
        #expect(store.business().lastInvoiceNumber == 2)
        #expect(store.lastInvoice()?.lines[1].price == 75)
        #expect(store.findItem("extra")?.lastPrice == 75)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Contact>()) == 1)
        #expect(files.exists("Invoice_2_2026-11-07.pdf"))
    }

    @Test func editContactMergesDuplicates() throws {
        let a = store.saveContact(ContactInfo(attention: "A", company: "One"))
        store.saveContact(ContactInfo(attention: "B", company: "Two"))
        store.updateContact(a, to: ContactInfo(attention: "B", company: "two"))
        let all = try container.mainContext.fetch(FetchDescriptor<Contact>())
        #expect(all.count == 1)
        #expect(all.first?.company == "two")
    }

    @Test func savingSameEntryMovesItToFront() throws {
        let early = Date(timeIntervalSince1970: 1000)
        store.saveItem("Deep clean", price: 250, at: early)
        store.saveItem("Window washing", price: 95, at: early.addingTimeInterval(10))
        store.saveItem("deep  CLEAN", price: 260, at: early.addingTimeInterval(20))
        let items = try container.mainContext.fetch(FetchDescriptor<SavedItem>(sortBy: [SortDescriptor(\.lastUsed, order: .reverse)]))
        #expect(items.map(\.itemDescription) == ["Deep clean", "Window washing"])
        #expect(items.first?.lastPrice == 260)
    }

    @Test func importCLIData() throws {
        var cli = CLIData()
        cli.sender = Sender(name: "Imported Co")
        cli.lastInvoiceNumber = 41
        cli.contacts = [ContactInfo(attention: "John Smith", company: "Acme LLC"), ContactInfo(attention: "B")]
        cli.jobAddresses = ["456 Oak Ave\nPlano, TX"]
        cli.items = [LineItem(description: "Deep clean", price: 250)]
        cli.lastInvoice = sampleInvoice(number: 41)
        let summary = try store.importCLI(cli)
        #expect(summary == Store.ImportSummary(contacts: 2, addresses: 1, items: 1, invoices: 1))
        let biz = store.business()
        #expect(biz.name == "Test Sender")          // existing profile is kept
        #expect(biz.nextInvoiceNumber == 42)
        #expect(store.repeatDraft()?.billTo.company == "Acme LLC")
        // Importing again adds nothing.
        #expect(try store.importCLI(cli) == Store.ImportSummary())
    }

    @Test func draftValidation() {
        let draft = InvoiceDraft(business: store.business())
        #expect(draft.missing == ["Bill to", "For", "a line item"])
        draft.taxText = "101"
        #expect(draft.taxRate == nil)
        draft.taxText = "8.25"
        draft.lines = [LineItem(description: "A", price: dec("10.06"))]
        #expect(draft.totals.tax == dec("0.83"))
        draft.numberText = "0"
        #expect(draft.number == nil)
    }
}
