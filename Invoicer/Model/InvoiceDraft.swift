import Foundation
import InvoicerKit
import Observation

/// The invoice being built in the sheet. Nothing here touches the invoice
/// counter: only `Store.finalize` (Confirm) does.
@MainActor
@Observable
final class InvoiceDraft: Identifiable {
    let id = UUID()
    /// Repeat opens straight on the review (= `invoice.py repeat`).
    let isRepeat: Bool
    var numberText: String
    var date: Date
    var contact: ContactInfo?
    var address: String?
    var lines: [LineItem]
    var taxText: String

    init(business: Business, today: Date = Date()) {
        isRepeat = false
        numberText = String(business.nextInvoiceNumber)
        date = Dates.day(today)
        contact = nil
        address = nil
        lines = []
        taxText = Money.formatRate(business.taxRate)
    }

    init(repeating last: InvoiceData, business: Business, today: Date = Date()) {
        isRepeat = true
        numberText = String(business.nextInvoiceNumber)
        date = Dates.day(today)
        contact = last.billTo
        address = last.jobAddress
        lines = last.items
        taxText = Money.formatRate(last.taxRate)
    }

    var number: Int? { try? Validate.invoiceNumber(numberText) }
    var taxRate: Decimal? { try? Money.parseRate(taxText) }
    var totals: Money.Totals { Money.totals(lines.map(\.price), rate: taxRate ?? 0) }

    /// Fields still needed before Review, in the prototype's wording.
    var missing: [String] {
        [contact == nil ? "Bill to" : nil, address == nil ? "For" : nil, lines.isEmpty ? "a line item" : nil]
            .compactMap { $0 }
    }

    var hasContent: Bool { contact != nil || address != nil || !lines.isEmpty }

    var data: InvoiceData? {
        guard let number, let taxRate, let contact, let address, !lines.isEmpty else { return nil }
        return InvoiceData(number: number, date: date, billTo: contact, jobAddress: address,
                           items: lines, taxRate: taxRate)
    }

    var filename: String { number.map { InvoiceData.filename(number: $0, date: date) } ?? "" }
}
