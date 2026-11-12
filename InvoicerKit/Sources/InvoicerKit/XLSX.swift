import Foundation

/// Read and edit the first visible worksheet of an .xlsx file in place, keeping
/// everything else in the package (styles, logo, formulas) untouched.
public struct XLSXWorkbook {
    public enum Value: Equatable, Sendable {
        case string(String)
        case number(Decimal)
        case date(Date)
        case formula(String)
    }

    var zip: ZipArchive
    let workbookPath: String
    let sheetPath: String
    let sheetIndex: Int
    public let sheetName: String
    var workbook: XElement
    var sheet: XElement
    var styles: XElement?
    var stylesPath: String?
    var sharedStrings: [String] = []
    private var dateStyleCache: [Int: Int] = [:]

    public struct XLSXError: LocalizedError, Sendable {
        public let message: String
        public var errorDescription: String? { message }
    }

    public init(data: Data) throws {
        do { zip = try ZipArchive(data: data) } catch {
            throw XLSXError(message: "That file isn't an .xlsx workbook")
        }
        guard let rootRels = zip["_rels/.rels"].flatMap({ try? XElement.parse($0) }),
              let docTarget = rootRels.all("Relationship").first(where: { ($0["Type"] ?? "").hasSuffix("/officeDocument") })?["Target"]
        else { throw XLSXError(message: "That file isn't an .xlsx workbook") }
        workbookPath = XLSXWorkbook.resolve(docTarget, from: "")
        guard let wbData = zip[workbookPath] else { throw XLSXError(message: "The workbook is missing") }
        workbook = try XElement.parse(wbData)

        let wbDir = (workbookPath as NSString).deletingLastPathComponent
        let relsPath = wbDir + "/_rels/" + (workbookPath as NSString).lastPathComponent + ".rels"
        let rels = try zip[relsPath].map(XElement.parse)?.all("Relationship") ?? []
        func target(id: String) -> String? { rels.first { $0["Id"] == id }?["Target"] }
        func target(typeSuffix: String) -> String? {
            rels.first { ($0["Type"] ?? "").hasSuffix(typeSuffix) }?["Target"]
        }

        // openpyxl's `wb.active`: the workbook view's active tab.
        let sheets = workbook.first("sheets")?.all("sheet") ?? []
        let active = Int(workbook.first("bookViews")?.first("workbookView")?["activeTab"] ?? "0") ?? 0
        sheetIndex = sheets.indices.contains(active) ? active : 0
        guard sheets.indices.contains(sheetIndex), let rid = sheets[sheetIndex]["r:id"], let sheetTarget = target(id: rid)
        else { throw XLSXError(message: "The workbook has no worksheet") }
        sheetName = sheets[sheetIndex]["name"] ?? "Sheet1"
        sheetPath = XLSXWorkbook.resolve(sheetTarget, from: wbDir)
        guard let sheetData = zip[sheetPath] else { throw XLSXError(message: "The worksheet is missing") }
        sheet = try XElement.parse(sheetData)

        if let t = target(typeSuffix: "/styles") {
            stylesPath = XLSXWorkbook.resolve(t, from: wbDir)
            styles = try zip[stylesPath!].map(XElement.parse)
        }
        if let t = target(typeSuffix: "/sharedStrings"), let data = zip[XLSXWorkbook.resolve(t, from: wbDir)] {
            sharedStrings = try XElement.parse(data).all("si").map(XLSXWorkbook.stringItemText)
        }
    }

    static func resolve(_ target: String, from dir: String) -> String {
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        var parts = dir.isEmpty ? [] : dir.split(separator: "/").map(String.init)
        for piece in target.split(separator: "/") {
            if piece == ".." { _ = parts.popLast() } else if piece != "." { parts.append(String(piece)) }
        }
        return parts.joined(separator: "/")
    }

    static func stringItemText(_ si: XElement) -> String {
        if let t = si.first("t") { return t.text }
        return si.all("r").compactMap { $0.first("t")?.text }.joined()
    }

    // MARK: cell addressing

    /// "G17" → (column 7, row 17)
    static func split(_ ref: String) -> (col: Int, row: Int) {
        var col = 0
        var digits = ""
        for ch in ref.uppercased() {
            if let a = ch.asciiValue, ch.isLetter { col = col * 26 + Int(a) - 64 } else { digits.append(ch) }
        }
        return (col, Int(digits) ?? 0)
    }

    static func columnName(_ index: Int) -> String {
        var n = index, s = ""
        while n > 0 { let r = (n - 1) % 26; s = String(UnicodeScalar(UInt8(65 + r))) + s; n = (n - 1) / 26 }
        return s
    }

    var sheetData: XElement { sheet.child("sheetData", order: XLSXWorkbook.worksheetOrder) }

    func findCell(_ ref: String) -> XElement? {
        let (_, row) = XLSXWorkbook.split(ref)
        guard let r = sheet.first("sheetData")?.all("row").first(where: { Int($0["r"] ?? "") == row }) else { return nil }
        return r.all("c").first { ($0["r"] ?? "").uppercased() == ref.uppercased() }
    }

    mutating func cell(_ ref: String) -> XElement {
        let (col, row) = XLSXWorkbook.split(ref)
        let data = sheetData
        let rowElement: XElement
        if let existing = data.all("row").first(where: { Int($0["r"] ?? "") == row }) {
            rowElement = existing
        } else {
            rowElement = XElement("row", [("r", String(row))])
            let index = data.children.firstIndex {
                if case .element(let e) = $0, e.name == "row", let r = Int(e["r"] ?? ""), r > row { return true }
                return false
            } ?? data.children.count
            data.children.insert(.element(rowElement), at: index)
        }
        rowElement["spans"] = nil   // an optimization hint; drop rather than keep it stale
        if let c = rowElement.all("c").first(where: { ($0["r"] ?? "").uppercased() == ref.uppercased() }) { return c }
        let c = XElement("c", [("r", ref.uppercased())])
        let index = rowElement.children.firstIndex {
            if case .element(let e) = $0, e.name == "c", XLSXWorkbook.split(e["r"] ?? "").col > col { return true }
            return false
        } ?? rowElement.children.count
        rowElement.children.insert(.element(c), at: index)
        return c
    }

    // MARK: reading

    public func value(_ ref: String) -> Value? {
        guard let c = findCell(ref) else { return nil }
        if let f = c.first("f") { return .formula(f.text) }
        let type = c["t"] ?? "n"
        switch type {
        case "inlineStr": return c.first("is").map { .string(XLSXWorkbook.stringItemText($0)) }
        case "s":
            guard let i = Int(c.first("v")?.text ?? ""), sharedStrings.indices.contains(i) else { return nil }
            return .string(sharedStrings[i])
        case "str", "e": return c.first("v").map { .string($0.text) }
        case "b": return c.first("v").map { .string($0.text == "1" ? "TRUE" : "FALSE") }
        default:
            guard let v = c.first("v")?.text, let number = Decimal(string: v, locale: Money.posix) else { return nil }
            if isDateFormat(styleIndex: Int(c["s"] ?? "0") ?? 0) { return .date(XLSXWorkbook.date(serial: number)) }
            return .number(number)
        }
    }

    public func string(_ ref: String) -> String? {
        if case .string(let s)? = value(ref) { return s }
        return nil
    }

    func numberFormat(styleIndex: Int) -> (id: Int, code: String) {
        let xfs = styles?.first("cellXfs")?.all("xf") ?? []
        guard xfs.indices.contains(styleIndex) else { return (0, "General") }
        let id = Int(xfs[styleIndex]["numFmtId"] ?? "0") ?? 0
        let custom = styles?.first("numFmts")?.all("numFmt").first { Int($0["numFmtId"] ?? "") == id }?["formatCode"]
        return (id, custom ?? XLSXWorkbook.builtinFormats[id] ?? "General")
    }

    static let builtinFormats: [Int: String] = [
        0: "General", 1: "0", 2: "0.00", 3: "#,##0", 4: "#,##0.00",
        5: "$#,##0_);($#,##0)", 6: "$#,##0_);[Red]($#,##0)", 7: "$#,##0.00_);($#,##0.00)",
        8: "$#,##0.00_);[Red]($#,##0.00)", 14: "mm-dd-yy", 15: "d-mmm-yy", 16: "d-mmm", 17: "mmm-yy",
        18: "h:mm AM/PM", 19: "h:mm:ss AM/PM", 20: "h:mm", 21: "h:mm:ss", 22: "m/d/yy h:mm",
        44: "_(\"$\"* #,##0.00_)_(\"$\"* \\(#,##0.00\\)_(\"$\"* \"-\"??_)_(@_)",
    ]

    func isDateFormat(styleIndex: Int) -> Bool {
        let (id, code) = numberFormat(styleIndex: styleIndex)
        if (14...22).contains(id) || (45...47).contains(id) { return true }
        // Ignore quoted literals and [color]/[$-locale] sections, then look for date tokens.
        let stripped = code.replacingOccurrences(of: #""[^"]*"|\[[^\]]*\]|\\."#, with: "", options: .regularExpression)
        return stripped.lowercased().contains { "dmy".contains($0) }
    }

    /// Like the CLI's `_cell_text`: dates as mm-dd-yy, currency cells as $1,234.56.
    public func display(_ ref: String) -> String {
        guard let v = value(ref) else { return "" }
        switch v {
        case .string(let s): return s.trimmed
        case .formula: return ""
        case .date(let d):
            let p = Dates.parts(d)
            return String(format: "%02d-%02d-%02d", p.month, p.day, p.year % 100)
        case .number(let n):
            let style = Int(findCell(ref)?["s"] ?? "0") ?? 0
            if numberFormat(styleIndex: style).code.contains("$") { return Money.format(n) }
            return NSDecimalNumber(decimal: n).description(withLocale: Money.posix)
        }
    }

    /// Column widths in character units (openpyxl's default is 13 when undefined).
    public func columnWidth(_ column: Int) -> Double {
        for col in sheet.first("cols")?.all("col") ?? [] {
            if let lo = Int(col["min"] ?? ""), let hi = Int(col["max"] ?? ""), (lo...hi).contains(column),
               let w = Double(col["width"] ?? ""), w > 0 {
                return w
            }
        }
        return 13
    }

    /// The first picture on the worksheet (the client's logo), if any.
    public func firstImage() -> Data? {
        let dir = (sheetPath as NSString).deletingLastPathComponent
        let relsPath = dir + "/_rels/" + (sheetPath as NSString).lastPathComponent + ".rels"
        guard let rels = zip[relsPath].flatMap({ try? XElement.parse($0) }),
              let drawingTarget = rels.all("Relationship").first(where: { ($0["Type"] ?? "").hasSuffix("/drawing") })?["Target"]
        else { return nil }
        let drawingPath = XLSXWorkbook.resolve(drawingTarget, from: dir)
        let drawingDir = (drawingPath as NSString).deletingLastPathComponent
        guard let drawing = zip[drawingPath].flatMap({ try? XElement.parse($0) }),
              let drawingRels = zip[drawingDir + "/_rels/" + (drawingPath as NSString).lastPathComponent + ".rels"]
                .flatMap({ try? XElement.parse($0) })
        else { return nil }
        func firstEmbed(_ e: XElement) -> String? {
            if e.name.hasSuffix("blip"), let id = e["r:embed"] { return id }
            for child in e.elements { if let id = firstEmbed(child) { return id } }
            return nil
        }
        guard let id = firstEmbed(drawing),
              let target = drawingRels.all("Relationship").first(where: { $0["Id"] == id })?["Target"] else { return nil }
        return zip[XLSXWorkbook.resolve(target, from: drawingDir)]
    }

    // MARK: writing

    /// Set a cell's value, keeping its style. nil empties the cell (style stays).
    public mutating func set(_ ref: String, _ value: Value?) {
        let c = cell(ref)
        c.removeAll(named: "v"); c.removeAll(named: "f"); c.removeAll(named: "is")
        c["t"] = nil
        switch value {
        case nil: break
        case .string(let s):
            c["t"] = "inlineStr"
            let t = XElement("t", children: [.text(s)])
            if s.first?.isWhitespace == true || s.last?.isWhitespace == true { t["xml:space"] = "preserve" }
            c.append(XElement("is", children: [.element(t)]))
        case .number(let n):
            c.append(XElement("v", children: [.text(NSDecimalNumber(decimal: n).description(withLocale: Money.posix))]))
        case .date(let d):
            c["s"] = String(dateStyle(basedOn: Int(c["s"] ?? "0") ?? 0))
            c.append(XElement("v", children: [.text(String(XLSXWorkbook.serial(d)))]))
        case .formula(let f):
            c.append(XElement("f", children: [.text(f)]))
        }
    }

    /// A cell style like `base` but with the `mm-dd-yy` number format (what openpyxl writes).
    mutating func dateStyle(basedOn base: Int) -> Int {
        if let cached = dateStyleCache[base] { return cached }
        if isDateFormat(styleIndex: base) && numberFormat(styleIndex: base).code == "mm-dd-yy" { return base }
        if styles == nil {
            styles = XElement("styleSheet", [("xmlns", "http://schemas.openxmlformats.org/spreadsheetml/2006/main")])
        }
        let order = ["numFmts", "fonts", "fills", "borders", "cellStyleXfs", "cellXfs", "cellStyles", "dxfs",
                     "tableStyles", "colors", "extLst"]
        // mm-dd-yy is built-in format 14 in en-US Excel, but openpyxl writes it as a custom code.
        let numFmts = styles!.child("numFmts", order: order)
        var fmtId = numFmts.all("numFmt").first { $0["formatCode"] == "mm-dd-yy" }.flatMap { Int($0["numFmtId"] ?? "") }
        if fmtId == nil {
            let next = max(163, numFmts.all("numFmt").compactMap { Int($0["numFmtId"] ?? "") }.max() ?? 163) + 1
            numFmts.append(XElement("numFmt", [("numFmtId", String(next)), ("formatCode", "mm-dd-yy")]))
            numFmts["count"] = String(numFmts.all("numFmt").count)
            fmtId = next
        }
        let cellXfs = styles!.child("cellXfs", order: order)
        if cellXfs.all("xf").isEmpty {
            cellXfs.append(XElement("xf", [("numFmtId", "0"), ("fontId", "0"), ("fillId", "0"), ("borderId", "0"), ("xfId", "0")]))
        }
        let xfs = cellXfs.all("xf")
        let source = xfs.indices.contains(base) ? xfs[base] : xfs[0]
        let copy = XElement("xf", source.attributes.map { ($0.name, $0.value) }, children: source.children)
        copy["numFmtId"] = String(fmtId!)
        copy["applyNumberFormat"] = "1"
        cellXfs.append(copy)
        cellXfs["count"] = String(cellXfs.all("xf").count)
        let index = cellXfs.all("xf").count - 1
        dateStyleCache[base] = index
        return index
    }

    static let worksheetOrder = ["sheetPr", "dimension", "sheetViews", "sheetFormatPr", "cols", "sheetData",
        "sheetCalcPr", "sheetProtection", "protectedRanges", "scenarios", "autoFilter", "sortState",
        "dataConsolidate", "customSheetViews", "mergeCells", "phoneticPr", "conditionalFormatting",
        "dataValidations", "hyperlinks", "printOptions", "pageMargins", "pageSetup", "headerFooter",
        "rowBreaks", "colBreaks", "customProperties", "cellWatches", "ignoredErrors", "smartTags", "drawing",
        "legacyDrawing", "legacyDrawingHF", "picture", "oleObjects", "controls", "webPublishItems",
        "tableParts", "extLst"]
    static let workbookOrder = ["fileVersion", "fileSharing", "workbookPr", "workbookProtection", "bookViews",
        "sheets", "functionGroups", "externalReferences", "definedNames", "calcPr", "oleSize",
        "customWorkbookViews", "pivotCaches", "smartTagPr", "smartTagTypes", "webPublishing", "fileRecoveryPr",
        "webPublishObjects", "extLst"]

    /// Print just `range`, portrait, one page wide.
    public mutating func setPrintArea(_ range: String) {
        let names = workbook.child("definedNames", order: XLSXWorkbook.workbookOrder)
        for existing in names.all("definedName")
        where existing["name"] == "_xlnm.Print_Area" && existing["localSheetId"] == String(sheetIndex) {
            names.remove(existing)
        }
        let quoted = "'" + sheetName.replacingOccurrences(of: "'", with: "''") + "'"
        let absolute = range.split(separator: ":").map { part -> String in
            let (c, r) = XLSXWorkbook.split(String(part))
            return "$\(XLSXWorkbook.columnName(c))$\(r)"
        }.joined(separator: ":")
        names.append(XElement("definedName", [("name", "_xlnm.Print_Area"), ("localSheetId", String(sheetIndex))],
                              children: [.text("\(quoted)!\(absolute)")]))

        let sheetPr = sheet.child("sheetPr", order: XLSXWorkbook.worksheetOrder)
        sheetPr.child("pageSetUpPr", order: ["tabColor", "outlinePr", "pageSetUpPr"])["fitToPage"] = "1"
        let setup = sheet.child("pageSetup", order: XLSXWorkbook.worksheetOrder)
        setup["orientation"] = "portrait"
        setup["fitToWidth"] = "1"
        setup["fitToHeight"] = "0"
    }

    /// Package bytes. Formulas lose cached values and Excel recalculates on open,
    /// like openpyxl output; the stale calc chain is dropped.
    public func serialized() -> Data {
        var zip = self.zip
        func stripCached(_ e: XElement) {
            if e.name == "c", e.first("f") != nil { e.removeAll(named: "v") }
            e.elements.forEach(stripCached)
        }
        stripCached(sheet)
        workbook.child("calcPr", order: XLSXWorkbook.workbookOrder)["fullCalcOnLoad"] = "1"

        if let chain = zip.names.first(where: { $0.hasSuffix("calcChain.xml") }) {
            zip[chain] = nil
            if let ct = zip["[Content_Types].xml"].flatMap({ try? XElement.parse($0) }) {
                for o in ct.all("Override") where (o["PartName"] ?? "").hasSuffix("calcChain.xml") { ct.remove(o) }
                zip["[Content_Types].xml"] = ct.serialized()
            }
            let wbDir = (workbookPath as NSString).deletingLastPathComponent
            let relsPath = wbDir + "/_rels/" + (workbookPath as NSString).lastPathComponent + ".rels"
            if let rels = zip[relsPath].flatMap({ try? XElement.parse($0) }) {
                for r in rels.all("Relationship") where (r["Type"] ?? "").hasSuffix("/calcChain") { rels.remove(r) }
                zip[relsPath] = rels.serialized()
            }
        }
        zip[workbookPath] = workbook.serialized()
        zip[sheetPath] = sheet.serialized()
        if let stylesPath, let styles { zip[stylesPath] = styles.serialized() }
        return zip.serialized()
    }

    // MARK: Excel dates (1900 system)

    static func serial(_ date: Date) -> Int {
        let p = Dates.parts(date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let epoch = utc.date(from: DateComponents(year: 1899, month: 12, day: 30))!
        let day = utc.date(from: DateComponents(year: p.year, month: p.month, day: p.day))!
        return Int((day.timeIntervalSince(epoch) / 86_400).rounded())
    }

    static func date(serial: Decimal) -> Date {
        let days = NSDecimalNumber(decimal: serial).intValue
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let d = utc.date(byAdding: .day, value: days, to: utc.date(from: DateComponents(year: 1899, month: 12, day: 30))!)!
        let c = utc.dateComponents([.year, .month, .day], from: d)
        return Dates.make(c.year!, c.month!, c.day!)!
    }
}
