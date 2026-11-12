import Foundation

/// The contents of the terminal app's `~/.invoicer/data.json`, read leniently
/// (missing keys get the CLI's defaults; numbers may be strings or numbers).
/// Lists keep the CLI's order: most recently used first.
public struct CLIData: Equatable, Sendable {
    public var sender = Sender()
    public var lastInvoiceNumber = 0
    public var defaultTaxRate = Decimal(string: "8.25")!
    public var contacts: [ContactInfo] = []
    public var jobAddresses: [String] = []
    public var items: [LineItem] = []
    public var lastInvoice: InvoiceData?
    public var contractor = Contractor()

    public init() {}

    public struct ImportError: LocalizedError, Sendable {
        public let message: String
        public var errorDescription: String? { message }
    }

    public init(json data: Data) throws {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ImportError(message: "That file isn't an Invoicer data.json")
        }
        guard root["sender"] != nil || root["contacts"] != nil || root["last_invoice_number"] != nil else {
            throw ImportError(message: "That file isn't an Invoicer data.json")
        }
        func str(_ any: Any?) -> String {
            switch any {
            case let s as String: return s
            case let n as NSNumber: return n.stringValue
            default: return ""
            }
        }
        func dict(_ any: Any?) -> [String: Any] { any as? [String: Any] ?? [:] }
        func decimal(_ any: Any?) -> Decimal? {
            let s = str(any)
            return s.isEmpty ? nil : (try? Money.parse(s)) ?? Decimal(string: s, locale: Money.posix)
        }
        func contact(_ any: Any?) -> ContactInfo {
            let c = dict(any)
            return ContactInfo(attention: str(c["attention"]), attention2: str(c["attention2"]),
                               company: str(c["company"]), street: str(c["street"]),
                               cityState: str(c["city_state"]), zip: str(c["zip"]))
        }
        func items(_ any: Any?) -> [LineItem] {
            (any as? [Any] ?? []).compactMap { entry in
                let i = dict(entry)
                let desc = str(i["description"])
                guard !desc.isEmpty, let price = decimal(i["price"]) else { return nil }
                return LineItem(description: desc, price: price)
            }
        }

        let s = dict(root["sender"])
        sender = Sender(name: str(s["name"]), phone: str(s["phone"]), email: str(s["email"]),
                        street: str(s["street"]), cityStateZip: str(s["city_state_zip"]),
                        payableTo: str(s["payable_to"]),
                        footerText: s["footer_text"] == nil ? Sender.defaultFooter : str(s["footer_text"]))
        lastInvoiceNumber = Int(str(root["last_invoice_number"])) ?? 0
        if let rate = try? Money.parseRate(str(root["default_tax_rate"])) { defaultTaxRate = rate }
        contacts = (root["contacts"] as? [Any] ?? []).map(contact)
        jobAddresses = (root["job_addresses"] as? [Any] ?? []).map(str).filter { !$0.isEmpty }
        self.items = items(root["items"])
        let c = dict(dict(root["weekly"])["contractor"])
        contractor = Contractor(name: str(c["name"]), street: str(c["street"]), address2: str(c["address2"]),
                                cityStateZip: str(c["city_state_zip"]), email: str(c["email"]), phone: str(c["phone"]))

        let last = dict(root["last_invoice"])
        if let number = Int(str(last["number"])), let date = try? Dates.parseMDY(str(last["date"])) {
            lastInvoice = InvoiceData(number: number, date: date, billTo: contact(last["bill_to"]),
                                      jobAddress: str(last["job_address"]), items: items(last["items"]),
                                      taxRate: (try? Money.parseRate(str(last["tax_rate"]))) ?? defaultTaxRate)
        }
    }
}
