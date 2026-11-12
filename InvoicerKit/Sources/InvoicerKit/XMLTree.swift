import Foundation

/// A tiny mutable XML element tree on top of Foundation's XMLParser (XMLDocument
/// isn't available on iOS). Good enough to edit OOXML parts and write them back.
public final class XElement {
    public var name: String
    public var attributes: [(name: String, value: String)]
    public var children: [XNode]

    public init(_ name: String, _ attributes: [(String, String)] = [], children: [XNode] = []) {
        self.name = name
        self.attributes = attributes.map { (name: $0.0, value: $0.1) }
        self.children = children
    }

    public subscript(attribute: String) -> String? {
        get { attributes.first { $0.name == attribute }?.value }
        set {
            if let i = attributes.firstIndex(where: { $0.name == attribute }) {
                if let newValue { attributes[i].value = newValue } else { attributes.remove(at: i) }
            } else if let newValue {
                attributes.append((attribute, newValue))
            }
        }
    }

    public var elements: [XElement] {
        children.compactMap { if case .element(let e) = $0 { return e } else { return nil } }
    }

    public func first(_ name: String) -> XElement? { elements.first { $0.name == name } }
    public func all(_ name: String) -> [XElement] { elements.filter { $0.name == name } }

    /// Concatenated text of this element and its descendants.
    public var text: String {
        children.map {
            switch $0 {
            case .text(let t): t
            case .element(let e): e.text
            }
        }.joined()
    }

    public func append(_ element: XElement) { children.append(.element(element)) }

    public func remove(_ element: XElement) {
        children.removeAll { if case .element(let e) = $0 { return e === element } else { return false } }
    }

    public func removeAll(named name: String) {
        children.removeAll { if case .element(let e) = $0 { return e.name == name } else { return false } }
    }

    /// Insert `element` among the children so that the schema's sibling order holds.
    public func insert(_ element: XElement, order: [String]) {
        guard let rank = order.firstIndex(of: element.name) else { append(element); return }
        let index = children.firstIndex {
            guard case .element(let e) = $0, let r = order.firstIndex(of: e.name) else { return false }
            return r > rank
        } ?? children.count
        children.insert(.element(element), at: index)
    }

    /// Existing child, or a new one inserted in schema order.
    public func child(_ name: String, order: [String]) -> XElement {
        if let existing = first(name) { return existing }
        let created = XElement(name)
        insert(created, order: order)
        return created
    }

    func write(to out: inout String) {
        out += "<" + name
        for (n, v) in attributes { out += " \(n)=\"\(XElement.escape(v, attribute: true))\"" }
        if children.isEmpty { out += "/>"; return }
        out += ">"
        for child in children {
            switch child {
            case .text(let t): out += XElement.escape(t, attribute: false)
            case .element(let e): e.write(to: &out)
            }
        }
        out += "</\(name)>"
    }

    public func serialized() -> Data {
        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        write(to: &out)
        return Data(out.utf8)
    }

    static func escape(_ s: String, attribute: Bool) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for ch in s.unicodeScalars {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"" where attribute: out += "&quot;"
            case "\n" where attribute: out += "&#10;"
            case "\r": out += "&#13;"
            case "\t" where attribute: out += "&#9;"
            default: out.unicodeScalars.append(ch)
            }
        }
        return out
    }

    public static func parse(_ data: Data) throws -> XElement {
        let delegate = TreeBuilder()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else {
            throw ZipArchive.ZipError(message: "Invalid XML: \(parser.parserError?.localizedDescription ?? "unknown")")
        }
        return root
    }
}

public enum XNode {
    case element(XElement)
    case text(String)
}

private final class TreeBuilder: NSObject, XMLParserDelegate {
    var stack: [XElement] = []
    var root: XElement?
    var pendingNamespaces: [(String, String)] = []

    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
        pendingNamespaces.append((prefix.isEmpty ? "xmlns" : "xmlns:" + prefix, namespaceURI))
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        var attrs = pendingNamespaces
        pendingNamespaces = []
        for (k, v) in attributeDict.sorted(by: { $0.key < $1.key }) where !attrs.contains(where: { $0.0 == k }) {
            attrs.append((k, v))
        }
        let element = XElement(qName ?? elementName, attrs)
        if let parent = stack.last { parent.append(element) } else { root = element }
        stack.append(element)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        stack.removeLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        appendText(string)
    }

    func parser(_ parser: XMLParser, foundIgnorableWhitespace whitespaceString: String) {
        appendText(whitespaceString)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        appendText(String(decoding: CDATABlock, as: UTF8.self))
    }

    private func appendText(_ s: String) {
        guard let parent = stack.last else { return }
        if case .text(let existing)? = parent.children.last {
            parent.children[parent.children.count - 1] = .text(existing + s)
        } else {
            parent.children.append(.text(s))
        }
    }
}
