import InvoicerKit
import SwiftData
import SwiftUI

/// First launch (= `invoice.py setup`). Values are committed on Continue so the
/// app doesn't switch to the tabs while the name is being typed.
struct SetupView: View {
    let business: Business
    @Environment(\.modelContext) private var context
    @Environment(Toast.self) private var toast

    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var street = ""
    @State private var cityStateZip = ""
    @State private var tax = "8.25"
    @State private var firstNumber = "1"
    @State private var importing = false

    private var taxValid: Bool { (try? Money.parseRate(tax)) != nil }
    private var numberValid: Bool { (try? Validate.invoiceNumber(firstNumber)) != nil }
    private var canContinue: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && taxValid && numberValid
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Invoicer · Setup").kickerStyle()
                    Text("Your details").largeTitleStyle().accessibilityAddTraits(.isHeader)
                    Text("These appear at the top of every invoice. Stored on this iPhone and synced to your iCloud.")
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .plainRow(top: 16, bottom: 4, horizontal: 20)
            }

            Section {
                FieldRow(label: "Name", text: $name, placeholder: "Required", first: true,
                         contentType: .organizationName)
                FieldRow(label: "Phone", text: $phone, placeholder: "(555) 555-0100",
                         keyboard: .phonePad, contentType: .telephoneNumber)
                FieldRow(label: "Email", text: $email, placeholder: "you@email.com",
                         keyboard: .emailAddress, contentType: .emailAddress, capitalization: .never)
                FieldRow(label: "Street", text: $street, placeholder: "2210 Main St",
                         contentType: .streetAddressLine1)
                FieldRow(label: "City", text: $cityStateZip, placeholder: "City, ST 12345",
                         contentType: .addressCityAndState)
            } header: { header("Business") }

            Section {
                TrailingFieldRow(label: "Default tax rate", text: $tax, suffix: "%", first: true,
                                 width: 64, invalid: !taxValid)
                TrailingFieldRow(label: "First invoice number", text: $firstNumber, keyboard: .numberPad,
                                 width: 80, invalid: !numberValid)
                Footnote("You can change these anytime in Settings.")
            } header: { header("Invoicing") }

            Section {
                Button("Continue", action: finish)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canContinue)
                    .plainRow(top: 34, bottom: 8, horizontal: 22)
                Button("Import from the terminal app") { importing = true }
                    .font(.barlow(15, FontName.medium, relativeTo: .subheadline))
                    .foregroundStyle(Color.accentInk)
                    .frame(maxWidth: .infinity)
                    .plainRow(top: 12, bottom: 24)
                    .accessibilityHint("Choose the data.json file from the Mac app's .invoicer folder")
            }
        }
        .industryList()
        .scrollDismissesKeyboard(.interactively)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            importCLI(result)
        }
    }

    private func finish() {
        business.name = name.trimmingCharacters(in: .whitespaces)
        business.phone = phone
        business.email = email
        business.street = street
        business.cityStateZip = cityStateZip
        if business.payableTo.isEmpty { business.payableTo = business.name }
        business.defaultTaxRate = Money.formatRate((try? Money.parseRate(tax)) ?? 0)
        business.lastInvoiceNumber = ((try? Validate.invoiceNumber(firstNumber)) ?? 1) - 1
        try? context.save()
    }

    private func importCLI(_ result: Result<URL, Error>) {
        do {
            let cli = try CLIData(json: readPickedFile(try result.get()))
            let summary = try Store(context: context).importCLI(cli)
            toast.show(summary.text)
        } catch {
            toast.show(error.localizedDescription)
        }
    }
}
