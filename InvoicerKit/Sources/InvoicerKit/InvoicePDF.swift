import CoreGraphics
import Foundation

/// Render an invoice to PDF. Port of the CLI's `pdf.py`.
///
/// The layout reproduces the reference invoice (a Pages template): blue rule and
/// sender name across the top, a left column with the invoice number and sender
/// contact info, and a right column with bill-to, date, job address, the line
/// item table and the footer notes. Coordinates are points on US Letter, text
/// is placed by baseline.
public enum InvoicePDF {
    // colors
    static let blue = PDFCanvas.rgb(54, 125, 162)
    static let black = PDFCanvas.rgb(0, 0, 0)
    static let white = PDFCanvas.rgb(255, 255, 255)
    static let titleGray = PDFCanvas.rgb(68, 68, 68)
    static let sideGray = PDFCanvas.rgb(96, 96, 96)
    static let gridGray = PDFCanvas.rgb(173, 173, 173)
    static let headerRule = PDFCanvas.rgb(127, 127, 127)
    static let edgeGray = PDFCanvas.rgb(228, 228, 228)

    // page frame (repeated on every page)
    static let ruleX0: CGFloat = 60, ruleX1: CGFloat = 552
    static let topRuleY: CGFloat = 56.5, topRuleW: CGFloat = 3
    static let nameBaseline: CGFloat = 76.8, nameSize: CGFloat = 13, nameTracking: CGFloat = 0.6
    static let bottomRuleY: CGFloat = 722
    static let pageNumBaseline: CGFloat = 738
    static let contentBottom: CGFloat = 700

    // left column
    static let leftX: CGFloat = 44.6
    static let titleBaseline: CGFloat = 213.25, titleSize: CGFloat = 18
    static let sideFirstBaseline: CGFloat = 241.5

    // right column
    static let colX: CGFloat = 190
    static let colRight: CGFloat = 550.4
    static let colW = colRight - colX
    static let billToBaseline: CGFloat = 186.1
    static let lineH: CGFloat = 14.35
    static let bodySize: CGFloat = 10
    static let tableGap: CGFloat = 20.2

    // table
    static let priceX: CGFloat = 448.84
    static let headerH: CGFloat = 20.69
    static let rowH: CGFloat = 20.76
    static let cellPad: CGFloat = 4.12
    static let rowBaseline: CGFloat = 13.8
    static let minItemRows = 5

    // footer notes
    static let notesGap: CGFloat = 36.8
    static let paraGap: CGFloat = 23.34

    enum Face: String {
        case light = "HelveticaNeue-Light", medium = "HelveticaNeue-Medium", bold = "HelveticaNeue-Bold"
    }

    static func face(_ pdf: PDFCanvas, _ face: Face, _ size: CGFloat = bodySize, _ color: CGColor = black) {
        pdf.setFont(face.rawValue, size: size, color: color)
    }

    public static func render(sender: Sender, invoice: InvoiceData) -> Data {
        let pdf = PDFCanvas(title: "Invoice #\(invoice.number)", author: sender.name)
        let name = sender.name.uppercased()
        pdf.onPageStart = { pdf in
            pdf.hline(ruleX0, ruleX1, topRuleY, topRuleW, blue)
            face(pdf, .bold, nameSize, blue)
            pdf.charSpacing = nameTracking
            pdf.put(ruleX0, nameBaseline, name)
            pdf.charSpacing = 0
        }
        pdf.onPageEnd = { pdf in
            pdf.hline(ruleX0, ruleX1, bottomRuleY, 1, blue)
            face(pdf, .medium, bodySize, sideGray)
            pdf.put(0, pageNumBaseline, String(pdf.pageNumber), right: ruleX1)
        }
        pdf.addPage()
        leftColumn(pdf, sender, invoice)
        var y = rightColumn(pdf, invoice)
        y = table(pdf, invoice, top: y + tableGap)
        notes(pdf, sender, baseline: y + notesGap)
        return pdf.finish()
    }

    static func leftColumn(_ pdf: PDFCanvas, _ sender: Sender, _ invoice: InvoiceData) {
        face(pdf, .light, titleSize, titleGray)
        pdf.put(leftX, titleBaseline, "INVOICE #\(invoice.number)")

        var y = sideFirstBaseline
        let rows: [(String?, CGColor?)] = [(sender.phone, sideGray), (sender.email, blue), (nil, nil),
                                           (sender.street, sideGray), (sender.cityStateZip, sideGray)]
        for (value, color) in rows {
            if let value, !value.isEmpty, let color {
                face(pdf, .medium, bodySize, color)
                pdf.put(leftX, y, value)
                y += lineH
            } else if color == nil {
                y += lineH
            }
        }
    }

    /// "Label" in bold blue followed by value in light black; value may wrap.
    static func labeled(_ pdf: PDFCanvas, _ baseline: CGFloat, _ label: String, _ value: String) -> CGFloat {
        var baseline = baseline
        face(pdf, .bold, bodySize, blue)
        let labelW = pdf.put(colX, baseline, label)
        face(pdf, .light)
        let lines = pdf.wrap(value, width: colW - labelW)
        pdf.put(colX + labelW, baseline, lines[0])
        for line in lines.dropFirst() {
            baseline += lineH
            pdf.put(colX, baseline, line)
        }
        return baseline
    }

    /// Bill-to, date and job address. Returns the baseline of the last line.
    static func rightColumn(_ pdf: PDFCanvas, _ invoice: InvoiceData) -> CGFloat {
        let contact = invoice.billTo
        var y = billToBaseline
        face(pdf, .bold, bodySize, blue)
        let w = pdf.put(colX, y, "Attention")
        face(pdf, .light)
        pdf.put(colX + w, y, ": \(contact.attention)")
        for line in contact.lines {
            y += lineH
            pdf.put(colX, y, line)
        }
        y = labeled(pdf, y + 2 * lineH, "Date:", " \(Dates.mdy(invoice.date))")
        return labeled(pdf, y + 2 * lineH, "For: ", invoice.jobAddress)
    }

    static func tableHeader(_ pdf: PDFCanvas, top: CGFloat) -> CGFloat {
        pdf.fill(CGRect(x: colX, y: top, width: colW, height: headerH), blue)
        pdf.hline(colX, colRight, top, 0.25, edgeGray)
        pdf.hline(colX, colRight, top + headerH, 0.5, headerRule)
        face(pdf, .bold, bodySize, white)
        pdf.put(colX + cellPad, top + 13.67, "Description")
        pdf.put(priceX + cellPad, top + 13.67, "Unit Price")
        return top + headerH
    }

    /// Light outer edges and the dashed column divider for a block of rows.
    static func tableFrame(_ pdf: PDFCanvas, top: CGFloat, bottom: CGFloat) {
        pdf.vline(colX, top, bottom, 0.25, edgeGray)
        pdf.vline(colRight, top, bottom, 0.25, edgeGray)
        pdf.vline(priceX, top, bottom, 0.75, gridGray, dashed: true)
    }

    /// Line items padded to `minItemRows`, then tax and total rows. Returns bottom y.
    static func table(_ pdf: PDFCanvas, _ invoice: InvoiceData, top: CGFloat) -> CGFloat {
        let totals = invoice.totals
        let descW = priceX - colX - 2 * cellPad

        var rows = invoice.items.map { ($0.description, Money.format($0.price)) }
        while rows.count < minItemRows { rows.append(("", "")) }

        var y = tableHeader(pdf, top: top)
        var blockTop = y
        face(pdf, .light)
        for (i, (desc, price)) in rows.enumerated() {
            let lines = desc.isEmpty ? [""] : pdf.wrap(desc, width: descW)
            let rowHeight = rowH + lineH * CGFloat(lines.count - 1)
            if y + rowHeight + 2 * rowH > contentBottom && i < rows.count - 1 {
                tableFrame(pdf, top: blockTop, bottom: y)
                pdf.addPage()
                y = tableHeader(pdf, top: topRuleY + 60)
                blockTop = y
                face(pdf, .light)
            }
            for (n, line) in lines.enumerated() {
                pdf.put(colX + cellPad, y + rowBaseline + CGFloat(n) * lineH, line)
            }
            pdf.put(0, y + rowBaseline, price, right: colRight - cellPad)
            y += rowHeight
            pdf.hline(colX, colRight, y, 0.75, gridGray, dashed: true)
        }

        // Tax row
        face(pdf, .bold)
        pdf.put(colX + cellPad, y + rowBaseline, "Tax (\(Money.formatRate(invoice.taxRate))%)")
        face(pdf, .light)
        pdf.put(0, y + rowBaseline, Money.format(totals.tax), right: colRight - cellPad)
        y += rowH
        pdf.hline(colX - 0.4, colRight + 0.5, y, 1, black)

        // Total row (no label, as in the reference)
        pdf.put(0, y + rowBaseline, Money.format(totals.total), right: colRight - cellPad)
        y += rowH
        pdf.hline(colX - 0.4, colRight + 0.5, y, 1, black)
        tableFrame(pdf, top: blockTop, bottom: y)
        return y
    }

    static func notes(_ pdf: PDFCanvas, _ sender: Sender, baseline: CGFloat) {
        let payable = sender.payableTo.isEmpty ? sender.name : sender.payableTo
        let contact = [sender.name, sender.phone, sender.email].filter { !$0.isEmpty }.joined(separator: " | ")
        let notes: [(String, CGColor)] = [
            ("Make all checks payable to \(payable)", black),
            (sender.footerText, black),
            ("If you have any questions, contact \(contact)", black),
            ("THANK YOU FOR YOUR BUSINESS", blue),
        ]
        face(pdf, .light)
        let blocks = notes.filter { !$0.0.isEmpty }.map { (pdf.wrap($0.0, width: colW), $0.1) }
        let height = blocks.reduce(CGFloat(0)) { $0 + lineH * CGFloat($1.0.count - 1) }
            + paraGap * CGFloat(blocks.count - 1)
        var baseline = baseline
        if baseline + height > contentBottom {
            pdf.addPage()
            baseline = topRuleY + 80
        }
        for (lines, color) in blocks {
            face(pdf, .light, bodySize, color)
            for (n, line) in lines.enumerated() {
                pdf.put(colX, baseline + CGFloat(n) * lineH, line)
            }
            baseline += lineH * CGFloat(lines.count - 1) + paraGap
        }
    }
}

/// Fake data for the demo invoice (port of `demo.py`). Never touches real data.
public enum Demo {
    public static let sender = Sender(
        name: "Jane Doe Cleaning", phone: "(555) 555-0100", email: "jane@example.com",
        street: "123 Example Street", cityStateZip: "Springfield, TX 75000",
        payableTo: "Jane Doe Cleaning", footerText: Sender.defaultFooter)

    public static let invoice = InvoiceData(
        number: 1001, date: Dates.make(2026, 1, 15)!,
        billTo: ContactInfo(attention: "John Sample", attention2: "Mary Placeholder",
                            company: "Example Property Management LLC",
                            street: "456 Demo Avenue, Suite 200", cityState: "Springfield, TX", zip: "75000"),
        jobAddress: "789 Fictional Lane, Unit 4B\nSpringfield, TX 75001",
        items: [
            LineItem(description: "Deep clean", price: 250),
            LineItem(description: "Carpet shampoo - 3 rooms", price: 180),
            LineItem(description: "Window washing (interior and exterior)", price: Decimal(string: "95.50")!),
        ],
        taxRate: Decimal(string: "8.25")!)

    public static func pdf() -> Data { InvoicePDF.render(sender: sender, invoice: invoice) }
}
