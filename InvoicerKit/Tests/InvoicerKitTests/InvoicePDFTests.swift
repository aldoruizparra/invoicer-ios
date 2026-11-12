import Foundation
import PDFKit
import Testing
@testable import InvoicerKit

struct InvoicePDFTests {
    /// Set INVOICER_SNAPSHOT_DIR to also write the demo PDF for a visual check.
    @Test func demoInvoice() throws {
        let data = Demo.pdf()
        if let dir = ProcessInfo.processInfo.environment["INVOICER_SNAPSHOT_DIR"] {
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("demo_invoice.pdf"))
        }
        let doc = try #require(PDFDocument(data: data))
        #expect(doc.pageCount == 1)
        #expect(doc.page(at: 0)?.bounds(for: .mediaBox).size == CGSize(width: 612, height: 792))
        let text = try #require(doc.string)
        for expected in ["JANE DOE CLEANING", "INVOICE #1001", "Attention: John Sample",
                         "Example Property Management LLC", "Springfield, TX 75000", "01/15/2026",
                         "789 Fictional Lane, Unit 4B", "Deep clean", "$250.00", "$95.50",
                         "Tax (8.25%)", "$43.35", "$568.85",
                         "Make all checks payable to Jane Doe Cleaning",
                         "THANK YOU FOR YOUR BUSINESS"] {
            #expect(text.contains(expected), "missing \(expected)")
        }
        #expect(doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Invoice #1001")
    }

    @Test func longInvoiceAddsPages() throws {
        var invoice = Demo.invoice
        invoice.items = (1...40).map { LineItem(description: "Item \($0) with a fairly long description that wraps onto a second line in the table", price: 10) }
        let doc = try #require(PDFDocument(data: InvoicePDF.render(sender: Demo.sender, invoice: invoice)))
        #expect(doc.pageCount > 1)
        let all = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
        #expect(all.contains("Item 40"))
        #expect(all.contains("$433.00"))   // 400 + 8.25% tax
    }
}
