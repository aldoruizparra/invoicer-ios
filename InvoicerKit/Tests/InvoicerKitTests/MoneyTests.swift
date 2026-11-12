import Foundation
import Testing
@testable import InvoicerKit

/// Port of tests/test_invoicer.py MoneyTests + validator tests.
struct MoneyTests {
    func d(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }

    @Test func parseMoney() throws {
        #expect(try Money.parse("$1,234.5") == d("1234.50"))
        #expect(try Money.parse("250") == d("250.00"))
        #expect(try Money.parse(" 1 000.50 ") == d("1000.50"))
        for bad in ["", "abc", "1.234", "nan", "inf", "12.x", "1e5"] {
            #expect(throws: Money.ParseError.self) { try Money.parse(bad) }
        }
    }

    @Test func taxRoundsHalfUp() {
        // 10.06 * 8.25% = 0.82995 -> 0.83 ; 0.30 * 8.25% = 0.02475 -> 0.02
        #expect(Money.totals([d("10.06")], rate: d("8.25")).tax == d("0.83"))
        #expect(Money.totals([d("0.30")], rate: d("8.25")).tax == d("0.02"))
        // 2.00 * 6.25% = 0.125 -> 0.13 (banker's rounding would give 0.12)
        #expect(Money.totals([d("2.00")], rate: d("6.25")).tax == d("0.13"))
    }

    @Test func totals() {
        let t = Money.totals([d("250.00"), d("180.00"), d("95.50")], rate: d("8.25"))
        #expect(t == Money.Totals(subtotal: d("525.50"), tax: d("43.35"), total: d("568.85")))
    }

    @Test func formatting() throws {
        #expect(Money.format(d("1234.5")) == "$1,234.50")
        #expect(Money.format(d("-5")) == "-$5.00")
        #expect(Money.format(d("0")) == "$0.00")
        #expect(Money.format(d("1234567.891")) == "$1,234,567.89")
        #expect(Money.formatRate(d("8.250")) == "8.25")
        #expect(Money.formatRate(d("10")) == "10")
        #expect(Money.plain(d("250")) == "250.00")
        #expect(Money.plain(d("95.5")) == "95.50")
        #expect(try Money.parseRate("8.25%") == d("8.25"))
        #expect(throws: Money.ParseError.self) { try Money.parseRate("101") }
        #expect(throws: Money.ParseError.self) { try Money.parseRate("-1") }
    }

    @Test func cents() {
        #expect(Money.cents(d("1000.50")) == 100050)
        #expect(Money.fromCents(100050) == d("1000.50"))
    }

    @Test func validators() throws {
        #expect(throws: Never.self) { try Dates.parseMDY("02/29/2028") }
        #expect(throws: Money.ParseError.self) { try Dates.parseMDY("02/30/2026") }
        #expect(throws: Money.ParseError.self) { try Dates.parseMDY("2026-10-16") }
        #expect(throws: Money.ParseError.self) { try Validate.invoiceNumber("0") }
        #expect(try Validate.invoiceNumber("#1044") == 1044)
        for good in ["", "78701", "78701-1234"] { #expect(throws: Never.self) { try Validate.zip(good) } }
        for bad in ["7870", "787011", "abcde", "78701-12"] {
            #expect(throws: Money.ParseError.self) { try Validate.zip(bad) }
        }
    }

    @Test func zipOnCityLine() {
        let contact = ContactInfo(attention: "A", company: "Co", cityState: "Austin, TX", zip: "78701")
        #expect(contact.lines == ["Co", "Austin, TX 78701"])
        #expect(ContactInfo(attention: "A", street: "1 St").lines == ["1 St"])
        #expect(Strings.cityLine("Plano, TX", "75024") == "Plano, TX 75024")
        #expect(Strings.jobAddress(street: "456 Oak Ave", cityState: "Plano, TX", zip: "") == "456 Oak Ave\nPlano, TX")
    }

    @Test func filename() {
        #expect(InvoiceData.filename(number: 1044, date: Dates.make(2026, 11, 7)!) == "Invoice_1044_2026-11-07.pdf")
    }

    @Test func contactKeyIgnoresCaseAndSpacing() {
        let a = ContactInfo(attention: "John  Smith", company: "Acme LLC")
        let b = ContactInfo(attention: "john smith", company: "ACME llc ")
        #expect(a.key == b.key)
    }
}
