import CoreGraphics
import Foundation

/// Weekly contractor invoice: fill the client's .xlsx template from a work-log
/// email, and draw a one-page-wide PDF of the result. Port of the CLI's `weekly.py`.
public enum WeeklyInvoice {
    // Cell layout of the "Weekly Invoice Sheet" template.
    static func contractorCells(_ c: Contractor) -> [(String, String)] {
        [(c.name, "C9"), (c.street, "C10"), (c.address2, "C11"),
         (c.cityStateZip, "C12"), (c.email, "C13"), (c.phone, "C14")]
    }
    static let periodStartCell = "E10", periodEndCell = "E11"
    static let firstRow = 17, lastRow = 100
    // Job columns; Job #, City/State and Service aren't in the email and stay blank.
    static let colClient = "A", colAddress = "C", colDate = "E", colAmount = "G"
    public static var capacity: Int { lastRow - firstRow + 1 }

    /// Check a template before saving it: must open as a workbook.
    public static func validateTemplate(_ data: Data) throws {
        _ = try XLSXWorkbook(data: data)
    }

    /// Contractor info, period dates and jobs written into a copy of the template.
    public static func fill(template: Data, contractor: Contractor, log: WeeklyLog) throws -> Data {
        if log.jobs.count > capacity {
            throw XLSXWorkbook.XLSXError(message: "The template has room for \(capacity) jobs; this email has \(log.jobs.count)")
        }
        var wb = try XLSXWorkbook(data: template)
        for (value, cell) in contractorCells(contractor) {
            wb.set(cell, value.isEmpty ? nil : .string(value))
        }
        wb.set(periodStartCell, log.periodStart.map { .date($0) })
        wb.set(periodEndCell, log.periodEnd.map { .date($0) })
        for (offset, job) in log.jobs.enumerated() {
            let row = firstRow + offset
            wb.set("\(colClient)\(row)", job.client.isEmpty ? nil : .string(job.client))
            wb.set("\(colAddress)\(row)", job.address.isEmpty ? nil : .string(job.address))
            wb.set("\(colDate)\(row)", .date(job.date))
            wb.set("\(colAmount)\(row)", job.amount.map { .number($0) })
        }
        wb.setPrintArea("A1:G\(lastRow + 1)")
        return wb.serialized()
    }

    // PDF colors taken from the template's theme.
    static let titleRule = PDFCanvas.rgb(91, 155, 213)
    static let nameRule = PDFCanvas.rgb(112, 173, 71)
    static let grid = PDFCanvas.rgb(68, 114, 196)
    static let link = PDFCanvas.rgb(5, 99, 193)
    static let black = PDFCanvas.rgb(0, 0, 0)
    static let tableCols = ["A", "B", "C", "D", "E", "F", "G"]
    static let minTableRows = 10

    /// One-page-wide Letter PDF of the filled sheet (only the rows in use).
    public static func pdf(xlsx: Data) throws -> Data {
        let ws = try XLSXWorkbook(data: xlsx)
        let widths = (1...7).map { CGFloat(ws.columnWidth($0)) }
        let margin: CGFloat = 36
        let pdf = PDFCanvas(title: "Weekly Invoice", author: ws.display("C9"))
        pdf.addPage()
        let pageW = pdf.page.width - 2 * margin
        let colW = widths.map { $0 / widths.reduce(0, +) * pageW }
        let colX = colW.indices.map { i in margin + colW[..<i].reduce(0, +) }

        func put(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ value: String,
                 bold: Bool = false, underline: Bool = false, size: CGFloat = 10,
                 align: PDFCanvas.Align = .left, color: CGColor = black) {
            pdf.setFont(bold ? "TimesNewRomanPS-BoldMT" : "TimesNewRomanPSMT", size: size, color: color)
            pdf.cell(x, y, w, h, value, align: align)
            if underline, !value.isEmpty {
                let tw = pdf.width(value)
                let tx = align == .center ? x + (w - tw) / 2 : x + PDFCanvas.cellMargin
                pdf.hline(tx, tx + tw, y + h / 2 + size * 0.45, 0.5, color)
            }
        }
        func rule(_ x0: CGFloat, _ x1: CGFloat, _ y: CGFloat, _ width: CGFloat, _ color: CGColor) {
            pdf.hline(x0, x1, y, width, color)
        }

        // Logo, placed over the right-hand columns like the sheet.
        var y = margin
        if let logo = ws.firstImage(), let h = pdf.image(logo, x: colX[4], y: y, width: 110) {
            y += h + 8
        }

        // Title (merged A8:F8) with the blue rule, then the contractor row with the green rule.
        let titleW = colW[..<6].reduce(0, +)
        put(margin, y, titleW, 20, ws.display("A8"), bold: true, size: 16, align: .center)
        y += 20
        rule(margin, margin + titleW, y, 2.5, titleRule)
        y += 2
        put(margin, y, colW[0] + colW[1], 14, ws.display("A9"), bold: true)
        put(colX[2], y, colW[2] + colW[3], 14, ws.display("C9"), bold: true)
        put(colX[5], y, colW[5], 14, ws.display("F9"), align: .center, color: link)
        y += 14
        rule(margin, margin + titleW, y, 2.5, nameRule)
        y += 2

        let rowH: CGFloat = 14
        for r in 10...14 {
            put(margin, y, colW[0] + colW[1], rowH, ws.display("A\(r)"))
            put(colX[2], y, colW[2], rowH, ws.display("C\(r)"))
            rule(colX[2], colX[3], y + rowH - 1, 0.5, black)
            if !ws.display("D\(r)").isEmpty {
                put(colX[3], y, colW[3], rowH, ws.display("D\(r)"), align: .right)
                put(colX[4], y, colW[4], rowH, ws.display("E\(r)"), align: .right)
                rule(colX[4], colX[5], y + rowH - 1, 0.5, grid)
            }
            y += rowH
        }
        y += rowH

        func tableHeader(_ y: CGFloat) -> CGFloat {
            for (i, c) in tableCols.enumerated() {
                put(colX[i], y, colW[i], rowH, ws.display("\(c)16"), bold: true, underline: true, align: .center)
            }
            return y + rowH
        }

        let used = (firstRow...lastRow).filter { r in tableCols.contains { ws.value("\($0)\(r)") != nil } }
        var rows: [Int?] = used
        while rows.count < minTableRows { rows.append(nil) }
        var total = Decimal(0)
        y = tableHeader(y)
        let bottom = pdf.page.height - margin - 2 * rowH
        for r in rows {
            if y + rowH > bottom {
                pdf.addPage()
                y = tableHeader(margin)
            }
            for i in tableCols.indices {
                pdf.stroke(CGRect(x: colX[i], y: y, width: colW[i], height: rowH), width: 0.6, color: grid)
            }
            if let r {
                for (i, c) in tableCols.enumerated() {
                    put(colX[i] + 2, y, colW[i] - 4, rowH, ws.display("\(c)\(r)"),
                        align: c == colAmount ? .right : .center)
                }
                if case .number(let amount)? = ws.value("\(colAmount)\(r)") { total += amount }
            }
            y += rowH
        }

        let totalLabel = ws.display("A\(lastRow + 1)")
        put(margin, y + 4, colW[0], 16, totalLabel.isEmpty ? "TOTAL" : totalLabel, bold: true, size: 12)
        put(colX[6] - 40, y + 4, colW[6] + 38, 16, Money.format(total), bold: true, size: 12, align: .right)
        return pdf.finish()
    }

    /// The PDF that goes next to `Weekly_Invoice_….xlsx`.
    public static func pdfFilename(for xlsxName: String) -> String {
        (xlsxName as NSString).deletingPathExtension + ".pdf"
    }
}
