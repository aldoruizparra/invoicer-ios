import Compression
import Foundation

/// Just enough ZIP to read and rewrite an .xlsx package (no zip64, no encryption).
/// DEFLATE comes from Apple's Compression framework (COMPRESSION_ZLIB = raw DEFLATE).
public struct ZipArchive: Sendable {
    public struct ZipError: LocalizedError, Sendable {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// Entries in their original order.
    public private(set) var names: [String] = []
    private var files: [String: Data] = [:]

    public init() {}

    public init(data: Data) throws {
        let b = [UInt8](data)
        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }

        // End of central directory: scan back over a possible comment.
        guard b.count >= 22 else { throw ZipError(message: "Not a zip file") }
        var eocd = -1
        var i = b.count - 22
        while i >= max(0, b.count - 22 - 65_535) {
            if b[i] == 0x50, b[i + 1] == 0x4B, b[i + 2] == 0x05, b[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError(message: "Not a zip file") }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)

        for _ in 0..<count {
            guard p + 46 <= b.count, u32(p) == 0x0201_4B50 else { throw ZipError(message: "Corrupt zip directory") }
            let method = u16(p + 10)
            let compressedSize = u32(p + 20), size = u32(p + 24)
            let nameLen = u16(p + 28), extraLen = u16(p + 30), commentLen = u16(p + 32)
            let localOffset = u32(p + 42)
            let name = String(decoding: b[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            p += 46 + nameLen + extraLen + commentLen

            guard localOffset + 30 <= b.count, u32(localOffset) == 0x0403_4B50 else {
                throw ZipError(message: "Corrupt zip entry \(name)")
            }
            let start = localOffset + 30 + u16(localOffset + 26) + u16(localOffset + 28)
            guard start + compressedSize <= b.count else { throw ZipError(message: "Truncated zip entry \(name)") }
            let raw = Data(b[start..<(start + compressedSize)])
            switch method {
            case 0: files[name] = raw
            case 8: files[name] = try ZipArchive.inflate(raw, size: size)
            default: throw ZipError(message: "Unsupported compression in \(name)")
            }
            names.append(name)
        }
    }

    public subscript(name: String) -> Data? {
        get { files[name] }
        set {
            if let newValue {
                if files[name] == nil { names.append(name) }
                files[name] = newValue
            } else {
                files[name] = nil
                names.removeAll { $0 == name }
            }
        }
    }

    public func serialized() -> Data {
        var out = Data()
        var central = Data()
        func put16(_ d: inout Data, _ v: Int) { d.append(UInt8(v & 0xFF)); d.append(UInt8(v >> 8 & 0xFF)) }
        func put32(_ d: inout Data, _ v: Int) { put16(&d, v & 0xFFFF); put16(&d, v >> 16 & 0xFFFF) }
        let dosTime = 0, dosDate = (2026 - 1980) << 9 | 1 << 5 | 1

        for name in names {
            let content = files[name]!
            let crc = ZipArchive.crc32(content)
            let deflated = ZipArchive.deflate(content)
            let (method, payload) = deflated.map { (8, $0) } ?? (0, content)
            let nameBytes = Data(name.utf8)
            let offset = out.count

            put32(&out, 0x0403_4B50); put16(&out, 20); put16(&out, 0x0800); put16(&out, method)
            put16(&out, dosTime); put16(&out, dosDate); put32(&out, Int(crc))
            put32(&out, payload.count); put32(&out, content.count)
            put16(&out, nameBytes.count); put16(&out, 0)
            out.append(nameBytes); out.append(payload)

            put32(&central, 0x0201_4B50); put16(&central, 20); put16(&central, 20); put16(&central, 0x0800)
            put16(&central, method); put16(&central, dosTime); put16(&central, dosDate); put32(&central, Int(crc))
            put32(&central, payload.count); put32(&central, content.count)
            put16(&central, nameBytes.count); put16(&central, 0); put16(&central, 0)
            put16(&central, 0); put16(&central, 0); put32(&central, 0); put32(&central, offset)
            central.append(nameBytes)
        }
        let centralOffset = out.count
        out.append(central)
        put32(&out, 0x0605_4B50); put16(&out, 0); put16(&out, 0)
        put16(&out, names.count); put16(&out, names.count)
        put32(&out, central.count); put32(&out, centralOffset); put16(&out, 0)
        return out
    }

    static func inflate(_ data: Data, size: Int) throws -> Data {
        if size == 0 { return Data() }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw ZipError(message: "Could not decompress zip entry") }
        return output
    }

    /// Raw DEFLATE, or nil when it doesn't help (then the entry is stored).
    static func deflate(_ data: Data) -> Data? {
        guard data.count > 64 else { return nil }
        let capacity = data.count + 1024
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0, written < data.count else { return nil }
        return output.prefix(written)
    }

    static let crcTable: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}
