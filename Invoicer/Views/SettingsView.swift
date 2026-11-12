import InvoicerKit
import SwiftData
import SwiftUI

/// Settings: business info (= `invoice.py setup`), invoicing defaults, tools
/// (import from the terminal app) and storage. The weekly sheet has its own tab.
struct SettingsView: View {
    @Bindable var business: Business
    let cloudAvailable: Bool

    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Environment(FileStore.self) private var files
    @Environment(Toast.self) private var toast
    @AppStorage("iCloudSync") private var syncEnabled = true

    @State private var name = ""
    @State private var taxText = ""
    @State private var nextText = ""
    @State private var importing = false

    private var taxRate: Decimal? { try? Money.parseRate(taxText) }
    private var nextNumber: Int? { try? Validate.invoiceNumber(nextText) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    FieldRow(label: "Name", text: $name, placeholder: "Required", first: true,
                             contentType: .organizationName, invalid: name.trimmingCharacters(in: .whitespaces).isEmpty)
                    FieldRow(label: "Phone", text: $business.phone, keyboard: .phonePad, contentType: .telephoneNumber)
                    FieldRow(label: "Email", text: $business.email, keyboard: .emailAddress,
                             contentType: .emailAddress, capitalization: .never)
                    FieldRow(label: "Street", text: $business.street, contentType: .streetAddressLine1)
                    FieldRow(label: "City", text: $business.cityStateZip, placeholder: "City, ST 12345",
                             contentType: .addressCityAndState)
                    FieldRow(label: "Pay to", text: $business.payableTo, placeholder: business.name)
                    FieldRow(label: "Footer", text: $business.footerText, placeholder: "Note on every invoice",
                             capitalization: .sentences)
                } header: { header("Your business") }

                Section {
                    TrailingFieldRow(label: "Default tax rate", text: $taxText, suffix: "%", first: true,
                                     width: 64, invalid: taxRate == nil)
                    TrailingFieldRow(label: "Next invoice number", text: $nextText, keyboard: .numberPad,
                                     width: 80, invalid: nextNumber == nil)
                } header: { header("Invoicing") }

                Section {
                    Button { importing = true } label: {
                        HStack(spacing: 12) {
                            TwoLineLabel(title: "Import from the terminal app",
                                         subtitle: "Contacts, addresses, items and invoice number from data.json")
                            Chevron()
                        }
                    }
                    .buttonStyle(RowButtonStyle(first: true)).listRowChrome()
                    #if DEBUG
                    Button(action: showDemo) {
                        HStack(spacing: 12) {
                            TwoLineLabel(title: "Demo invoice", subtitle: "Debug: render the demo PDF from fake data")
                            Chevron()
                        }
                    }
                    .buttonStyle(RowButtonStyle()).listRowChrome()
                    #endif
                } header: { header("Tools") }

                Section {
                    Toggle("iCloud sync", isOn: $syncEnabled)
                        .toggleStyle(SquareToggleStyle())
                        .hairlineCell(first: true)
                    Footnote(storageNote)
                        .padding(.bottom, 24)
                } header: { header("Storage") }
            }
            .industryList()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: name) { _, v in
            let t = v.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { business.name = t }
        }
        .onChange(of: taxText) { if let taxRate { business.defaultTaxRate = Money.formatRate(taxRate) } }
        .onChange(of: nextText) { if let nextNumber { business.lastInvoiceNumber = nextNumber - 1 } }
        .onChange(of: business.lastInvoiceNumber) { _, last in
            if nextNumber != last + 1 { nextText = String(last + 1) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let cli = try CLIData(json: readPickedFile(try result.get()))
                let summary = try Store(context: context).importCLI(cli)
                load()
                toast.show(summary.text)
            } catch {
                toast.show(error.localizedDescription)
            }
        }
    }

    private var storageNote: String {
        if !syncEnabled { return "Everything stays on this iPhone only. PDFs are kept in Files › On My iPhone › Invoicer." }
        if !cloudAvailable || (files.resolvedICloud && files.iCloudDocuments == nil) {
            return "iCloud isn't available right now (sign in to iCloud in the Settings app). Everything is saved on this iPhone until it is."
        }
        return "Invoices, contacts and items sync across your devices with iCloud. PDFs are kept in iCloud Drive › Invoicer."
    }

    private func load() {
        name = business.name
        taxText = business.defaultTaxRate
        nextText = String(business.nextInvoiceNumber)
    }

    #if DEBUG
    private func showDemo() {
        router.preview = PreviewItem(filename: "demo_invoice.pdf", data: Demo.pdf(), url: nil)
    }
    #endif
}
