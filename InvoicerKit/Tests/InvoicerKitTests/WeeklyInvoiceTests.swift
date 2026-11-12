import Foundation
import PDFKit
import Testing
@testable import InvoicerKit

/// Port of tests/test_weekly.py FillTests. The fixture template is made with openpyxl
/// from fake data; set INVOICER_SNAPSHOT_DIR to keep the outputs for inspection.
struct WeeklyInvoiceTests {
    let template = try! Data(contentsOf: Bundle.module.url(forResource: "weekly_template", withExtension: "xlsx",
                                                           subdirectory: "Fixtures")!)
    let contractor = Contractor(name: "Jane Sample", street: "1 Demo St.", address2: "",
                                cityStateZip: "Springfield, TX 75001", email: "", phone: "")

    @Test func fillAndPDF() throws {
        let log = try EmailLogParser.parse(sampleLog)
        let out = try WeeklyInvoice.fill(template: template, contractor: contractor, log: log)
        let ws = try XLSXWorkbook(data: out)
        #expect(ws.string("C9") == "Jane Sample")
        #expect(ws.value("C11") == nil)
        #expect(ws.value("E10") == .date(Dates.make(2026, 10, 4)!))
        #expect(ws.display("E10") == "10-04-26")
        #expect(ws.string("A17") == "Acme Homes")
        #expect(ws.string("C17") == "100 First St")
        #expect(ws.value("G17") == .number(65))
        #expect(ws.display("G21") == "$1,050.25")
        #expect(ws.value("G22") == nil)          // blank amount stays blank
        #expect(ws.value("A23") == nil)          // nothing past the last job
        #expect(ws.value("G101") == .formula("SUM(G17:G100)"))
        #expect(ws.string("A16") == "Client")    // template labels untouched
        #expect(ws.firstImage() != nil)          // logo kept

        let pdf = try WeeklyInvoice.pdf(xlsx: out)
        let doc = try #require(PDFDocument(data: pdf))
        let text = try #require(doc.string)
        for s in ["Weekly Invoice Sheet", "Jane Sample", "Acme Homes", "500 Fifth Dr.", "10-09-26", "$1,290.25", "TOTAL"] {
            #expect(text.contains(s), "missing \(s)")
        }
        if let dir = ProcessInfo.processInfo.environment["INVOICER_SNAPSHOT_DIR"] {
            let url = URL(fileURLWithPath: dir)
            try out.write(to: url.appendingPathComponent(log.filename))
            try pdf.write(to: url.appendingPathComponent(WeeklyInvoice.pdfFilename(for: log.filename)))
        }
    }

    @Test func fillsJobNumberCityAndService() throws {
        var log = try EmailLogParser.parse(sampleLog)
        log.jobs[0].jobNumber = "4521"
        log.jobs[0].cityState = "Springfield, TX"
        log.jobs[0].service = "Move-out clean"
        log.jobs[1].jobNumber = "A-17"
        log.jobs[2].jobNumber = "0042"
        let ws = try XLSXWorkbook(data: WeeklyInvoice.fill(template: template, contractor: contractor, log: log))
        #expect(ws.value("B17") == .number(4521))
        #expect(ws.string("D17") == "Springfield, TX")
        #expect(ws.string("F17") == "Move-out clean")
        #expect(ws.string("B18") == "A-17")
        #expect(ws.string("B19") == "0042")          // leading zero kept as text
        #expect(ws.value("D18") == nil)               // blank stays blank
        #expect(ws.value("F18") == nil)
        let text = try #require(PDFDocument(data: try WeeklyInvoice.pdf(xlsx: WeeklyInvoice.fill(
            template: template, contractor: contractor, log: log)))?.string)
        for s in ["4521", "Springfield, TX", "Move-out clean", "A-17"] { #expect(text.contains(s), "missing \(s)") }
    }

    @Test func tooManyJobs() throws {
        var log = try EmailLogParser.parse(sampleLog)
        log.jobs = Array(repeating: log.jobs[0], count: WeeklyInvoice.capacity + 1)
        #expect(throws: XLSXWorkbook.XLSXError.self) {
            try WeeklyInvoice.fill(template: template, contractor: contractor, log: log)
        }
    }

    @Test func rejectsNonWorkbook() {
        #expect(throws: XLSXWorkbook.XLSXError.self) { try WeeklyInvoice.validateTemplate(Data("hello".utf8)) }
    }

    @Test func zipRoundTrip() throws {
        var zip = ZipArchive()
        zip["a.txt"] = Data(String(repeating: "hello ", count: 200).utf8)
        zip["b/c.bin"] = Data([0, 1, 2])
        let back = try ZipArchive(data: zip.serialized())
        #expect(back.names == ["a.txt", "b/c.bin"])
        #expect(back["a.txt"] == zip["a.txt"])
        #expect(back["b/c.bin"] == Data([0, 1, 2]))
        #expect(ZipArchive.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test func excelSerials() {
        #expect(XLSXWorkbook.serial(Dates.make(2026, 10, 4)!) == 46299)
        #expect(XLSXWorkbook.date(serial: 46299) == Dates.make(2026, 10, 4))
        #expect(XLSXWorkbook.columnName(28) == "AB")
        #expect(XLSXWorkbook.split("AB12").col == 28)
    }
}
