import Foundation
import InvoicerKit
import SwiftData

// SwiftData models. CloudKit sync needs every attribute to have a default and no
// unique constraints, so uniqueness (invoice numbers, saved entries) is enforced
// in `Store`. Money is stored as integer cents, tax rates as decimal strings.

@Model
final class Business {
    var createdAt = Date()
    var name = ""
    var phone = ""
    var email = ""
    var street = ""
    var cityStateZip = ""
    var payableTo = ""
    var footerText = Sender.defaultFooter
    /// Percent, e.g. "8.25".
    var defaultTaxRate = "8.25"
    /// Like the CLI's `last_invoice_number`: the next invoice defaults to this + 1.
    var lastInvoiceNumber = 0

    // Weekly contractor invoice
    var contractorName = ""
    var contractorStreet = ""
    var contractorAddress2 = ""
    var contractorCityStateZip = ""
    var contractorEmail = ""
    var contractorPhone = ""
    var templateName = ""

    init() {}

    var isSetUp: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    var nextInvoiceNumber: Int { lastInvoiceNumber + 1 }
    var taxRate: Decimal { (try? Money.parseRate(defaultTaxRate)) ?? 0 }

    var sender: Sender {
        Sender(name: name, phone: phone, email: email, street: street, cityStateZip: cityStateZip,
               payableTo: payableTo, footerText: footerText)
    }

    var contractor: Contractor {
        get {
            Contractor(name: contractorName, street: contractorStreet, address2: contractorAddress2,
                       cityStateZip: contractorCityStateZip, email: contractorEmail, phone: contractorPhone)
        }
        set {
            contractorName = newValue.name; contractorStreet = newValue.street
            contractorAddress2 = newValue.address2; contractorCityStateZip = newValue.cityStateZip
            contractorEmail = newValue.email; contractorPhone = newValue.phone
        }
    }
}

@Model
final class Contact {
    var attention = ""
    var attention2 = ""
    var company = ""
    var street = ""
    var cityState = ""
    var zip = ""
    var lastUsed = Date()

    init(_ info: ContactInfo, lastUsed: Date = Date()) {
        self.info = info
        self.lastUsed = lastUsed
    }

    var info: ContactInfo {
        get { ContactInfo(attention: attention, attention2: attention2, company: company,
                          street: street, cityState: cityState, zip: zip) }
        set {
            attention = newValue.attention; attention2 = newValue.attention2; company = newValue.company
            street = newValue.street; cityState = newValue.cityState; zip = newValue.zip
        }
    }
}

@Model
final class JobAddress {
    /// "street\ncity, state zip" (second line optional), as in the CLI.
    var text = ""
    var lastUsed = Date()

    init(_ text: String, lastUsed: Date = Date()) {
        self.text = text
        self.lastUsed = lastUsed
    }

    var label: String { Strings.addressLabel(text) }
}

@Model
final class SavedItem {
    var itemDescription = ""
    var lastPriceCents = 0
    var lastUsed = Date()

    init(description: String, price: Decimal, lastUsed: Date = Date()) {
        itemDescription = description
        lastPriceCents = Money.cents(price)
        self.lastUsed = lastUsed
    }

    var lastPrice: Decimal {
        get { Money.fromCents(lastPriceCents) }
        set { lastPriceCents = Money.cents(newValue) }
    }
}

@Model
final class Invoice {
    var number = 0
    var date = Date()
    var createdAt = Date()
    // Snapshot of the bill-to contact and job address at the time of the invoice.
    var attention = ""
    var attention2 = ""
    var company = ""
    var street = ""
    var cityState = ""
    var zip = ""
    var jobAddress = ""
    /// JSON-encoded [StoredLine].
    var linesData = Data()
    var taxRate = "0"
    /// File name of the saved PDF (resolved against the current PDF folder).
    var pdfFilename = ""

    init(_ data: InvoiceData) {
        self.data = data
    }

    struct StoredLine: Codable {
        var description: String
        var priceCents: Int
    }

    var billTo: ContactInfo {
        ContactInfo(attention: attention, attention2: attention2, company: company,
                    street: street, cityState: cityState, zip: zip)
    }

    var lines: [LineItem] {
        let stored = (try? JSONDecoder().decode([StoredLine].self, from: linesData)) ?? []
        return stored.map { LineItem(description: $0.description, price: Money.fromCents($0.priceCents)) }
    }

    var data: InvoiceData {
        get {
            InvoiceData(number: number, date: date, billTo: billTo, jobAddress: jobAddress, items: lines,
                        taxRate: (try? Money.parseRate(taxRate)) ?? 0)
        }
        set {
            number = newValue.number
            date = Dates.day(newValue.date)
            let c = newValue.billTo
            attention = c.attention; attention2 = c.attention2; company = c.company
            street = c.street; cityState = c.cityState; zip = c.zip
            jobAddress = newValue.jobAddress
            linesData = (try? JSONEncoder().encode(newValue.items.map {
                StoredLine(description: $0.description, priceCents: Money.cents($0.price))
            })) ?? Data()
            taxRate = Money.formatRate(newValue.taxRate)
            pdfFilename = newValue.filename
        }
    }

    var total: Decimal { data.totals.total }
}

enum Schema1 {
    static let models: [any PersistentModel.Type] = [Business.self, Contact.self, JobAddress.self,
                                                     SavedItem.self, Invoice.self,
                                                     WeekSheet.self, WorkJob.self]
}
