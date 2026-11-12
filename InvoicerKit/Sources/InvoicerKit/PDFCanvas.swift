import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// Minimal fpdf-like drawing surface on a CoreGraphics PDF context.
/// Coordinates are points from the top-left (y grows down), text is placed by baseline.
final class PDFCanvas {
    static let letter = CGRect(x: 0, y: 0, width: 612, height: 792)

    private let data = NSMutableData()
    private let context: CGContext
    let page: CGRect
    private(set) var pageNumber = 0
    private var font: CTFont
    private var color: CGColor = PDFCanvas.rgb(0, 0, 0)
    var charSpacing: CGFloat = 0
    /// fpdf's default cell margin (1 cm / 10) — multi_cell wraps inside it.
    static let cellMargin: CGFloat = 28.35 / 10

    var onPageStart: ((PDFCanvas) -> Void)?
    var onPageEnd: ((PDFCanvas) -> Void)?

    init(title: String, author: String, page: CGRect = PDFCanvas.letter) {
        self.page = page
        var box = page
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let info: [CFString: Any] = [kCGPDFContextTitle: title, kCGPDFContextAuthor: author,
                                     kCGPDFContextCreator: "Invoicer"]
        context = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary)!
        font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
    }

    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
        CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    func addPage() {
        if pageNumber > 0 { endPage() }
        context.beginPDFPage(nil)
        pageNumber += 1
        context.saveGState()
        // Flip to a top-left origin like fpdf.
        context.translateBy(x: 0, y: page.height)
        context.scaleBy(x: 1, y: -1)
        onPageStart?(self)
    }

    private func endPage() {
        onPageEnd?(self)
        context.restoreGState()
        context.endPDFPage()
    }

    func finish() -> Data {
        if pageNumber > 0 { endPage() }
        context.closePDF()
        return data as Data
    }

    // MARK: text

    func setFont(_ name: String, size: CGFloat, color: CGColor) {
        font = CTFontCreateWithName(name as CFString, size, nil)
        self.color = color
    }

    private func line(_ text: String) -> CTLine {
        var attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        if charSpacing != 0 { attrs[NSAttributedString.Key(kCTKernAttributeName as String)] = charSpacing }
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    }

    func width(_ text: String) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line(text), nil, nil, nil))
    }

    /// Draw one line at a baseline; `right` right-aligns to that x. Returns the width.
    @discardableResult
    func put(_ x: CGFloat, _ baseline: CGFloat, _ text: String, right: CGFloat? = nil) -> CGFloat {
        let l = line(text)
        let w = CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil))
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: right.map { $0 - w } ?? x, y: baseline)
        CTLineDraw(l, context)
        context.restoreGState()
        return w
    }

    /// Draw text centered/aligned in a box (used by the weekly sheet).
    func cell(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ text: String,
              align: Align = .left) {
        guard !text.isEmpty else { return }
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        let baseline = y + h / 2 + (ascent - descent) / 2
        let tw = width(text)
        let pad = PDFCanvas.cellMargin
        let tx: CGFloat
        switch align {
        case .left: tx = x + pad
        case .center: tx = x + (w - tw) / 2
        case .right: tx = x + w - pad - tw
        }
        put(tx, baseline, text)
    }

    enum Align { case left, center, right }

    /// Greedy word wrap like fpdf's multi_cell(dry_run=True, output=LINES).
    func wrap(_ text: String, width: CGFloat) -> [String] {
        let maxWidth = width - 2 * PDFCanvas.cellMargin
        var result: [String] = []
        for para in text.components(separatedBy: "\n") {
            var lines: [String] = []
            var current = ""
            var started = false   // keeps leading spaces, like fpdf
            for word in para.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
                let candidate = started ? current + " " + word : word
                if self.width(candidate) <= maxWidth {
                    current = candidate
                    started = true
                    continue
                }
                if !current.isEmpty { lines.append(current); current = "" }
                started = true
                // A single word wider than the line breaks by characters.
                var chunk = ""
                for ch in word {
                    if self.width(chunk + String(ch)) > maxWidth, !chunk.isEmpty {
                        lines.append(chunk); chunk = ""
                    }
                    chunk.append(ch)
                }
                current = chunk
            }
            lines.append(current)
            result += lines
        }
        return result
    }

    // MARK: shapes

    func line(from a: CGPoint, to b: CGPoint, width: CGFloat, color: CGColor, dashed: Bool = false) {
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(width)
        if dashed { context.setLineDash(phase: 0, lengths: [1.5, 1.5]) }
        context.move(to: a)
        context.addLine(to: b)
        context.strokePath()
        context.restoreGState()
    }

    func hline(_ x0: CGFloat, _ x1: CGFloat, _ y: CGFloat, _ width: CGFloat, _ color: CGColor, dashed: Bool = false) {
        line(from: CGPoint(x: x0, y: y), to: CGPoint(x: x1, y: y), width: width, color: color, dashed: dashed)
    }

    func vline(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat, _ width: CGFloat, _ color: CGColor, dashed: Bool = false) {
        line(from: CGPoint(x: x, y: y0), to: CGPoint(x: x, y: y1), width: width, color: color, dashed: dashed)
    }

    func fill(_ rect: CGRect, _ color: CGColor) {
        context.setFillColor(color)
        context.fill(rect)
    }

    func stroke(_ rect: CGRect, width: CGFloat, color: CGColor) {
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(width)
        context.stroke(rect)
        context.restoreGState()
    }

    /// Draw an image (PNG/JPEG bytes) with its top-left at (x, y).
    func image(_ data: Data, x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width > 0 else { return nil }
        let height = width * CGFloat(image.height) / CGFloat(image.width)
        context.saveGState()
        // Images draw upright in the unflipped space.
        context.translateBy(x: x, y: y + height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.restoreGState()
        return height
    }
}
