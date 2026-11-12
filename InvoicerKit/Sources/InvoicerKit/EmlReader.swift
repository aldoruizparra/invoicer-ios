import Foundation

/// Extract the readable text body of an `.eml` file (RFC 822 / MIME).
/// Prefers text/plain; falls back to text/html with tags stripped, like the CLI's
/// `read_eml_text`. Handles multipart, quoted-printable, base64 and common charsets.
public enum EmlReader {
    public static func text(from data: Data) throws -> String {
        // Not a MIME message at all (e.g. a plain .txt work log): use the text as is.
        let head = String(decoding: data.prefix(2048), as: UTF8.self)
        if !MimePart.looksLikeHeaders(head) {
            return MimePart.decode(data, charset: nil)
        }
        let part = MimePart(raw: data)
        guard let body = part.bestBody(preferHTML: false) ?? part.bestBody(preferHTML: true) else {
            throw EmailLogError(message: "This email has no readable text body")
        }
        var text = body.decodedText
        if body.contentType == "text/html" { text = stripHTML(text) }
        return text
    }

    static let scriptRe = Re(#"<(script|style).*?</\1>"#, ignoreCase: true, dotAll: true)
    static let breakRe = Re(#"<br\s*/?>|</(p|div|tr|li|h\d)>"#, ignoreCase: true)
    static let tagRe = Re(#"<[^>]+>"#)

    static func stripHTML(_ html: String) -> String {
        var text = scriptRe.sub("", html)
        text = breakRe.sub("\n", text)
        return unescapeHTML(tagRe.sub(" ", text))
    }

    static let entityRe = Re(#"&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);"#)
    static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "ndash": "–", "mdash": "—", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
        "hellip": "…", "copy": "©", "reg": "®", "trade": "™", "middot": "·", "bull": "•",
    ]

    static func unescapeHTML(_ text: String) -> String {
        var out = ""
        var cursor = text.startIndex
        for m in entityRe.all(text) {
            out += text[cursor..<m.start]
            let name = m.group(1)!
            var replacement: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                replacement = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) }
            } else if name.hasPrefix("#") {
                replacement = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) }
            } else {
                replacement = namedEntities[name.lowercased()]
            }
            out += replacement ?? String(text[m.start..<m.end])
            cursor = m.end
        }
        out += text[cursor...]
        return out
    }
}

struct MimePart {
    var headers: [(name: String, value: String)] = []
    var body = Data()
    var children: [MimePart] = []

    init(raw: Data) {
        let (headerData, bodyData) = MimePart.splitHeaders(raw)
        headers = MimePart.parseHeaders(headerData)
        body = bodyData
        if contentType.hasPrefix("multipart/"), let boundary = parameter("boundary", of: "content-type") {
            children = MimePart.splitMultipart(bodyData, boundary: boundary).map(MimePart.init(raw:))
        }
    }

    /// True when the text starts with an RFC 822 header block (Name: value lines,
    /// then a blank line) that includes at least one real message header.
    static func looksLikeHeaders(_ text: String) -> Bool {
        var sawKnown = false
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return sawKnown }
            if line.first == " " || line.first == "\t" { continue }
            guard let colon = line.firstIndex(of: ":"),
                  line[..<colon].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return false }
            let name = line[..<colon].lowercased()
            if ["content-type", "mime-version", "subject", "date", "message-id", "received", "return-path"].contains(name) {
                sawKnown = true
            }
        }
        return false
    }

    func header(_ name: String) -> String? {
        headers.first { $0.name.lowercased() == name }?.value
    }

    /// Lowercased MIME type; defaults to text/plain.
    var contentType: String {
        guard let value = header("content-type") else { return "text/plain" }
        let type = value.split(separator: ";", maxSplits: 1).first.map { String($0).trimmed.lowercased() }
        return (type?.isEmpty ?? true) ? "text/plain" : type!
    }

    var isAttachment: Bool {
        (header("content-disposition") ?? "").trimmed.lowercased().hasPrefix("attachment")
    }

    func parameter(_ key: String, of headerName: String) -> String? {
        guard let value = header(headerName) else { return nil }
        for piece in value.split(separator: ";").dropFirst() {
            let kv = piece.split(separator: "=", maxSplits: 1)
            guard kv.count == 2, kv[0].trimmed.lowercased() == key else { continue }
            var v = kv[1].trimmed
            if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 { v = String(v.dropFirst().dropLast()) }
            return v
        }
        return nil
    }

    /// Depth-first: first non-attachment part of the wanted text type.
    func bestBody(preferHTML: Bool) -> MimePart? {
        let wanted = preferHTML ? "text/html" : "text/plain"
        if children.isEmpty { return (contentType == wanted && !isAttachment) ? self : nil }
        for child in children where !child.isAttachment {
            if let found = child.bestBody(preferHTML: preferHTML) { return found }
        }
        return nil
    }

    var decodedText: String {
        let encoding = (header("content-transfer-encoding") ?? "").trimmed.lowercased()
        let bytes: Data
        switch encoding {
        case "base64":
            let compact = String(decoding: body, as: UTF8.self).filter { !$0.isWhitespace }
            bytes = Data(base64Encoded: compact, options: .ignoreUnknownCharacters) ?? body
        case "quoted-printable":
            bytes = MimePart.decodeQuotedPrintable(body)
        default:
            bytes = body
        }
        return MimePart.decode(bytes, charset: parameter("charset", of: "content-type"))
    }

    // MARK: parsing helpers

    static func splitHeaders(_ raw: Data) -> (Data, Data) {
        let bytes = [UInt8](raw)
        var i = 0
        while i < bytes.count {
            if bytes[i] == 0x0A {
                // "\n\n" or "\n\r\n" ends the header block.
                if i + 1 < bytes.count, bytes[i + 1] == 0x0A { return (Data(bytes[..<i]), Data(bytes[(i + 2)...])) }
                if i + 2 < bytes.count, bytes[i + 1] == 0x0D, bytes[i + 2] == 0x0A {
                    return (Data(bytes[..<i]), Data(bytes[(i + 3)...]))
                }
            }
            i += 1
        }
        return (raw, Data())
    }

    static func parseHeaders(_ data: Data) -> [(name: String, value: String)] {
        let text = String(decoding: data, as: UTF8.self)
        var result: [(name: String, value: String)] = []
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            if let first = line.first, first == " " || first == "\t", !result.isEmpty {
                result[result.count - 1].value += " " + line.trimmed   // folded continuation
            } else if let colon = line.firstIndex(of: ":") {
                result.append((String(line[..<colon]).trimmed, String(line[line.index(after: colon)...]).trimmed))
            }
        }
        return result
    }

    static func splitMultipart(_ body: Data, boundary: String) -> [Data] {
        let text = [UInt8](body)
        let delimiter = Array(("--" + boundary).utf8)
        var parts: [Data] = []
        var lineStart = 0
        var partStart: Int?
        var i = 0
        func lineEnd(from start: Int) -> Int {
            var j = start
            while j < text.count, text[j] != 0x0A { j += 1 }
            return j
        }
        while lineStart <= text.count {
            let end = lineEnd(from: lineStart)
            var line = Array(text[lineStart..<end])
            if line.last == 0x0D { line.removeLast() }
            if line.starts(with: delimiter) {
                if let s = partStart {
                    // Drop the line break before the delimiter.
                    var e = lineStart
                    if e > s, text[e - 1] == 0x0A { e -= 1 }
                    if e > s, text[e - 1] == 0x0D { e -= 1 }
                    parts.append(Data(text[s..<max(s, e)]))
                }
                let rest = line.dropFirst(delimiter.count)
                if rest.starts(with: [0x2D, 0x2D]) { break }   // closing "--boundary--"
                partStart = end + 1
            }
            lineStart = end + 1
            i += 1
            if end >= text.count { break }
        }
        return parts
    }

    static func decodeQuotedPrintable(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        var out: [UInt8] = []
        var i = 0
        func hex(_ b: UInt8) -> UInt8? {
            switch b {
            case 0x30...0x39: return b - 0x30
            case 0x41...0x46: return b - 0x41 + 10
            case 0x61...0x66: return b - 0x61 + 10
            default: return nil
            }
        }
        while i < bytes.count {
            let b = bytes[i]
            if b == 0x3D {   // "="
                if i + 1 < bytes.count, bytes[i + 1] == 0x0A { i += 2; continue }   // soft break
                if i + 2 < bytes.count, bytes[i + 1] == 0x0D, bytes[i + 2] == 0x0A { i += 3; continue }
                if i + 2 < bytes.count, let h = hex(bytes[i + 1]), let l = hex(bytes[i + 2]) {
                    out.append(h << 4 | l); i += 3; continue
                }
            }
            out.append(b)
            i += 1
        }
        return Data(out)
    }

    static func decode(_ data: Data, charset: String?) -> String {
        if let charset {
            let cf = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            if cf != kCFStringEncodingInvalidId {
                let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
                if let s = String(data: data, encoding: encoding) { return s }
            }
        }
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }
}
