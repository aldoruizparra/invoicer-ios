import Foundation
import InvoicerKit
import SwiftData

/// The CLI's rules, on top of SwiftData: one business profile, most-recently-used
/// saved lists without duplicates, and invoice numbers that are only used up on
/// confirm.
@MainActor
struct Store {
    let context: ModelContext

    enum StoreError: LocalizedError, Equatable {
        case duplicateNumber(Int)
        case invalidNumber

        var errorDescription: String? {
            switch self {
            case .duplicateNumber(let n): "Invoice #\(String(n)) already exists."
            case .invalidNumber: "Invoice number must be a positive whole number."
            }
        }
    }

    // MARK: business

    /// The single business profile. With iCloud sync two devices may each have
    /// created one; the set-up, oldest one wins.
    func business() -> Business {
        let all = (try? context.fetch(FetchDescriptor<Business>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        if let best = all.first(where: \.isSetUp) ?? all.first { return best }
        let created = Business()
        context.insert(created)
        return created
    }

    // MARK: invoices

    func invoiceExists(_ number: Int) -> Bool {
        let descriptor = FetchDescriptor<Invoice>(predicate: #Predicate { $0.number == number })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    func lastInvoice() -> Invoice? {
        var descriptor = FetchDescriptor<Invoice>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// A draft prefilled from the last invoice with the next number and today's date
    /// (`invoice.py repeat`), or nil when there is no invoice yet.
    func repeatDraft(today: Date = Date()) -> InvoiceData? {
        guard var data = lastInvoice()?.data else { return nil }
        data.number = business().nextInvoiceNumber
        data.date = Dates.day(today)
        return data
    }

    /// Confirm: write the PDF, then record the invoice and bump the counter and the
    /// saved lists. Nothing changes if any step before that fails.
    @discardableResult
    func finalize(_ data: InvoiceData, files: FileStore) throws -> Invoice {
        guard data.number > 0 else { throw StoreError.invalidNumber }
        if invoiceExists(data.number) { throw StoreError.duplicateNumber(data.number) }
        let biz = business()
        let pdf = InvoicePDF.render(sender: biz.sender, invoice: data)
        try files.write(pdf, named: data.filename)

        let invoice = Invoice(data)
        context.insert(invoice)
        biz.lastInvoiceNumber = max(biz.lastInvoiceNumber, data.number)
        let now = Date()
        saveContact(data.billTo, at: now)
        saveAddress(data.jobAddress, at: now)
        // First line item ends up most recent, like the CLI's reversed push_front.
        for (offset, item) in data.items.enumerated().reversed() {
            saveItem(item.description, price: item.price, at: now.addingTimeInterval(-Double(offset) / 1000))
        }
        try context.save()
        return invoice
    }

    // MARK: saved lists (most recently used first, no duplicates)

    @discardableResult
    func saveContact(_ info: ContactInfo, at date: Date = Date()) -> Contact {
        let all = (try? context.fetch(FetchDescriptor<Contact>())) ?? []
        if let existing = all.first(where: { $0.info.key == info.key }) {
            existing.info = info
            existing.lastUsed = date
            return existing
        }
        let contact = Contact(info, lastUsed: date)
        context.insert(contact)
        return contact
    }

    /// Edit a saved contact; drop any other entry the edit made identical to it.
    func updateContact(_ contact: Contact, to info: ContactInfo) {
        contact.info = info
        let all = (try? context.fetch(FetchDescriptor<Contact>())) ?? []
        for other in all where other !== contact && other.info.key == info.key {
            context.delete(other)
        }
    }

    @discardableResult
    func saveAddress(_ text: String, at date: Date = Date()) -> JobAddress {
        let key = Strings.norm(text)
        let all = (try? context.fetch(FetchDescriptor<JobAddress>())) ?? []
        if let existing = all.first(where: { Strings.norm($0.text) == key }) {
            existing.text = text
            existing.lastUsed = date
            return existing
        }
        let address = JobAddress(text, lastUsed: date)
        context.insert(address)
        return address
    }

    func updateAddress(_ address: JobAddress, to text: String) {
        address.text = text
        let key = Strings.norm(text)
        let all = (try? context.fetch(FetchDescriptor<JobAddress>())) ?? []
        for other in all where other !== address && Strings.norm(other.text) == key { context.delete(other) }
    }

    /// Remember a line item's description and last price.
    @discardableResult
    func saveItem(_ description: String, price: Decimal, at date: Date = Date()) -> SavedItem {
        let key = Strings.norm(description)
        let all = (try? context.fetch(FetchDescriptor<SavedItem>())) ?? []
        if let existing = all.first(where: { Strings.norm($0.itemDescription) == key }) {
            existing.lastPrice = price
            existing.lastUsed = date
            return existing
        }
        let item = SavedItem(description: description, price: price, lastUsed: date)
        context.insert(item)
        return item
    }

    func updateItem(_ item: SavedItem, description: String, price: Decimal) {
        item.itemDescription = description
        item.lastPrice = price
        let key = Strings.norm(description)
        let all = (try? context.fetch(FetchDescriptor<SavedItem>())) ?? []
        for other in all where other !== item && Strings.norm(other.itemDescription) == key { context.delete(other) }
    }

    /// Exact (case/whitespace-insensitive) match for a typed description.
    func findItem(_ description: String) -> SavedItem? {
        let key = Strings.norm(description)
        let all = (try? context.fetch(FetchDescriptor<SavedItem>())) ?? []
        return all.first { Strings.norm($0.itemDescription) == key }
    }

    // MARK: import from the terminal app

    struct ImportSummary: Equatable {
        var contacts = 0, addresses = 0, items = 0, invoices = 0
        var text: String {
            "Imported \(contacts) contacts, \(addresses) addresses, \(items) items"
                + (invoices > 0 ? " and the last invoice" : "")
        }
    }

    /// Merge a CLI data.json: fill blank profile fields, keep the higher invoice
    /// counter, add saved entries (keeping their order, older than anything here).
    @discardableResult
    func importCLI(_ cli: CLIData) throws -> ImportSummary {
        let biz = business()
        let s = cli.sender
        if !biz.isSetUp {
            biz.name = s.name; biz.phone = s.phone; biz.email = s.email; biz.street = s.street
            biz.cityStateZip = s.cityStateZip; biz.payableTo = s.payableTo; biz.footerText = s.footerText
            biz.defaultTaxRate = Money.formatRate(cli.defaultTaxRate)
        }
        biz.lastInvoiceNumber = max(biz.lastInvoiceNumber, cli.lastInvoiceNumber)
        if biz.contractorName.isEmpty { biz.contractor = cli.contractor }

        var summary = ImportSummary()
        let oldest = [
            (try? context.fetch(FetchDescriptor<Contact>()))?.map(\.lastUsed).min(),
            (try? context.fetch(FetchDescriptor<JobAddress>()))?.map(\.lastUsed).min(),
            (try? context.fetch(FetchDescriptor<SavedItem>()))?.map(\.lastUsed).min(),
        ].compactMap { $0 }.min() ?? Date()
        func stamp(_ i: Int) -> Date { oldest.addingTimeInterval(-Double(i + 1)) }

        let contactKeys = Set(((try? context.fetch(FetchDescriptor<Contact>())) ?? []).map(\.info.key))
        for (i, c) in cli.contacts.enumerated() where !contactKeys.contains(c.key) {
            context.insert(Contact(c, lastUsed: stamp(i))); summary.contacts += 1
        }
        let addressKeys = Set(((try? context.fetch(FetchDescriptor<JobAddress>())) ?? []).map { Strings.norm($0.text) })
        for (i, a) in cli.jobAddresses.enumerated() where !addressKeys.contains(Strings.norm(a)) {
            context.insert(JobAddress(a, lastUsed: stamp(i))); summary.addresses += 1
        }
        let itemKeys = Set(((try? context.fetch(FetchDescriptor<SavedItem>())) ?? []).map { Strings.norm($0.itemDescription) })
        for (i, item) in cli.items.enumerated() where !itemKeys.contains(Strings.norm(item.description)) {
            context.insert(SavedItem(description: item.description, price: item.price, lastUsed: stamp(i)))
            summary.items += 1
        }
        if let last = cli.lastInvoice, !invoiceExists(last.number) {
            let invoice = Invoice(last)
            invoice.createdAt = Date.distantPast   // older than anything made in the app
            context.insert(invoice)
            summary.invoices = 1
        }
        try context.save()
        return summary
    }
}
