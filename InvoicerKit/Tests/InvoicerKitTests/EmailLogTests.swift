import Foundation
import Testing
@testable import InvoicerKit

/// Port of tests/test_weekly.py ParseTests. All data here is made up.
let sampleLog = """
To: Example Client Co
PO Box 1
Springfield, TX 75000
From: Jane Sample
1 Demo St.
Springfield, Tx. 75001
Invoice Date: 10/12//2026
Work Week:10/04//2026-10/11/2026
10/07- Acme Homes 100 First St $65
10/07- Acme Homes  200 Second . $65
This week, I also cleaned the patio furniture.
10/08- Beta 300 Third St $50.                          10/08- Gamma Co 400 Fourth Ln $60
10/09- Delta S. 500 Fifth Dr.$1,050.25
10/09- Echo H. 600 Sixth G $
Total: $1,290.25

"""

func dec(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }

struct EmailLogTests {
    let log = try! EmailLogParser.parse(sampleLog)

    @Test func header() {
        #expect(log.invoiceDate == Dates.make(2026, 10, 12))
        #expect(log.periodStart == Dates.make(2026, 10, 4))
        #expect(log.periodEnd == Dates.make(2026, 10, 11))
        #expect(log.senderLines == ["Jane Sample", "1 Demo St.", "Springfield, Tx. 75001"])
        #expect(log.statedTotal == dec("1290.25"))
    }

    @Test func jobs() {
        let got = log.jobs.map { [String(Dates.parts($0.date).day), $0.client, $0.address,
                                  $0.amount.map(Money.plain) ?? "nil"] }
        #expect(got == [
            ["7", "Acme Homes", "100 First St", "65.00"],
            ["7", "Acme Homes", "200 Second", "65.00"],
            ["8", "Beta", "300 Third St", "50.00"],
            ["8", "Gamma Co", "400 Fourth Ln", "60.00"],
            ["9", "Delta S.", "500 Fifth Dr.", "1050.25"],
            ["9", "Echo H.", "600 Sixth G", "nil"],
        ])
        #expect(log.notes == ["This week, I also cleaned the patio furniture."])
        #expect(log.jobs[5].source == "10/09- Echo H. 600 Sixth G $")
    }

    @Test func totalCheck() {
        // 1,290.25 parsed vs 1,290.25 stated: match until the blank job gets an amount.
        #expect(log.parsedTotal == dec("1290.25"))
        #expect(log.statedTotal == log.parsedTotal)
        #expect(log.missingCount == 1)
        var edited = log
        edited.jobs[5].amount = dec("40")
        #expect(edited.parsedTotal - edited.statedTotal! == dec("40"))
    }

    @Test func yearRollover() throws {
        let log = try EmailLogParser.parse("Work Week: 12/28/2026-01/03/2027\n12/30- A 1 St $5\n01/02- B 2 St $5\n")
        #expect(log.jobs.map(\.date) == [Dates.make(2026, 12, 30), Dates.make(2027, 1, 2)])
    }

    @Test func filename() {
        #expect(log.filename == "Weekly_Invoice_2026-10-04_to_2026-10-11.xlsx")
        #expect(log.suggestedContractor.cityStateZip == "Springfield, Tx. 75001")
    }

    @Test func readsPlainEml() throws {
        let eml = "Subject: Invoice\r\nContent-Type: text/plain; charset=\"utf-8\"\r\n"
            + "Content-Transfer-Encoding: 7bit\r\nMIME-Version: 1.0\r\n\r\n"
            + sampleLog.replacingOccurrences(of: "\n", with: "\r\n")
        let text = try EmlReader.text(from: Data(eml.utf8))
        #expect(try EmailLogParser.parse(text).jobs.count == 6)
    }

    @Test func readsMultipartQuotedPrintableAndHTML() throws {
        let qp = sampleLog.replacingOccurrences(of: "$1,290.25", with: "=241,290.25")
        let html = "<html><body><div>10/07- Html Only 1 St $5</div><br>Total: $5 &amp; more</body></html>"
        let eml = """
        From: x@example.com
        Content-Type: multipart/alternative; boundary="b1"

        --b1
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: quoted-printable

        \(qp)
        --b1
        Content-Type: text/html; charset=utf-8

        \(html)
        --b1--
        """
        let text = try EmlReader.text(from: Data(eml.utf8))
        let log = try EmailLogParser.parse(text)
        #expect(log.jobs.count == 6)
        #expect(log.statedTotal == dec("1290.25"))

        let htmlOnly = "Content-Type: text/html\nContent-Transfer-Encoding: base64\n\n"
            + Data(html.utf8).base64EncodedString(options: .lineLength64Characters)
        let htmlText = try EmlReader.text(from: Data(htmlOnly.utf8))
        #expect(try EmailLogParser.parse(htmlText).jobs.first?.client == "Html Only")
        #expect(htmlText.contains("$5 & more"))
    }

    @Test func plainTextWorkLogIsReadAsIs() throws {
        // The log itself starts with "To:" / "From:" lines but has no real message headers.
        let text = try EmlReader.text(from: Data(sampleLog.utf8))
        #expect(try EmailLogParser.parse(text).jobs.count == 6)
    }

    @Test func noBodyThrows() {
        let eml = "Content-Type: multipart/mixed; boundary=x\n\n--x\nContent-Type: image/png\n\nabc\n--x--\n"
        #expect(throws: EmailLogError.self) { try EmlReader.text(from: Data(eml.utf8)) }
    }
}
