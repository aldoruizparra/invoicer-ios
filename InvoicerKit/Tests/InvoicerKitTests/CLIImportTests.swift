import Foundation
import Testing
@testable import InvoicerKit

struct CLIImportTests {
    @Test func readsCLIDataFile() throws {
        let json = """
        {
          "sender": {"name": "Test Sender", "phone": "555-0100", "email": "t@example.com",
                     "street": "1 Main", "city_state_zip": "Dallas, TX 75201", "payable_to": "",
                     "footer_text": "Thanks."},
          "last_invoice_number": 7,
          "default_tax_rate": "8.25",
          "contacts": [{"attention": "John Smith", "attention2": "", "company": "Acme LLC",
                        "street": "1 Main St", "city_state": "Dallas, TX", "zip": "75201"},
                       {"attention": "B", "company": "Two"}],
          "job_addresses": ["456 Oak Ave\\nPlano, TX"],
          "items": [{"description": "Deep clean", "price": "250.00"}, {"description": "Extra", "price": "1000.50"}],
          "last_invoice": {"number": 7, "date": "10/16/2026",
                           "bill_to": {"attention": "John Smith", "company": "Acme LLC"},
                           "job_address": "456 Oak Ave\\nPlano, TX",
                           "items": [{"description": "Deep clean", "price": "250.00"}], "tax_rate": "8.25"},
          "weekly": {"contractor": {"name": "Jane Sample", "city_state_zip": "Springfield, TX"}}
        }
        """
        let data = try CLIData(json: Data(json.utf8))
        #expect(data.sender.name == "Test Sender")
        #expect(data.sender.footerText == "Thanks.")
        #expect(data.lastInvoiceNumber == 7)
        #expect(data.defaultTaxRate == dec("8.25"))
        #expect(data.contacts.map(\.company) == ["Acme LLC", "Two"])
        #expect(data.contacts[0].zip == "75201")
        #expect(data.jobAddresses == ["456 Oak Ave\nPlano, TX"])
        #expect(data.items.map(\.price) == [dec("250"), dec("1000.50")])
        #expect(data.lastInvoice?.number == 7)
        #expect(data.lastInvoice?.date == Dates.make(2026, 10, 16))
        #expect(data.lastInvoice?.filename == "Invoice_7_2026-10-16.pdf")
        #expect(data.contractor.name == "Jane Sample")
    }

    @Test func defaultsForFreshFile() throws {
        let data = try CLIData(json: Data(#"{"sender": {}, "last_invoice_number": 0, "last_invoice": null}"#.utf8))
        #expect(data.sender.footerText == Sender.defaultFooter)
        #expect(data.lastInvoice == nil)
        #expect(data.defaultTaxRate == dec("8.25"))
    }

    @Test func rejectsOtherJSON() {
        #expect(throws: CLIData.ImportError.self) { try CLIData(json: Data(#"{"hello": 1}"#.utf8)) }
        #expect(throws: CLIData.ImportError.self) { try CLIData(json: Data("not json".utf8)) }
    }
}
