import InvoicerKit
import SwiftData
import SwiftUI

/// New / Repeat invoice sheet: Form → pickers → line items → Review.
struct InvoiceSheet: View {
    @Bindable var draft: InvoiceDraft
    let business: Business
    @State private var path: [InvoiceRoute]
    @Environment(\.modelContext) private var context

    init(draft: InvoiceDraft, business: Business) {
        self.draft = draft
        self.business = business
        var initial: [InvoiceRoute] = draft.isRepeat ? [.review] : []
        #if DEBUG
        switch DebugLaunch.openScreen {
        case "contacts": initial = [.contacts]
        case "addresses": initial = [.addresses]
        case "item": initial = [.item(nil)]
        case "newContact": initial = [.contacts, .newContact("Chen Residence")]
        default: break
        }
        #endif
        _path = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack(path: $path) {
            InvoiceFormView(draft: draft, path: $path)
                .navigationDestination(for: InvoiceRoute.self) { route in
                    switch route {
                    case .contacts:
                        ContactPickerView(draft: draft, path: $path)
                    case .newContact(let name):
                        ContactEditorView(title: "New contact", initial: ContactInfo(attention: name)) { info in
                            Store(context: context).saveContact(info)   // saved right away, like the CLI
                            draft.contact = info
                            path.removeLast(min(2, path.count))
                        }
                    case .editContact(let id):
                        EditSavedContact(id: id) { old, new in
                            if draft.contact?.key == old.key { draft.contact = new }
                            path.removeLast()
                        }
                    case .addresses:
                        AddressPickerView(draft: draft, path: $path)
                    case .newAddress(let street):
                        AddressEditorView(title: "New job address", initial: street) { text in
                            Store(context: context).saveAddress(text)
                            draft.address = text
                            path.removeLast(min(2, path.count))
                        }
                    case .item(let index):
                        LineItemView(draft: draft, editing: index) { path.removeLast() }
                    case .review:
                        ReviewView(draft: draft, business: business, path: $path)
                    }
                }
        }
        .tint(.accentInk)
    }
}

enum InvoiceRoute: Hashable {
    case contacts
    case newContact(String)
    case editContact(PersistentIdentifier)
    case addresses
    case newAddress(String)
    case item(Int?)
    case review
}

/// The form (= the CLI's prompts): number, date, bill to, for, items, tax.
struct InvoiceFormView: View {
    @Bindable var draft: InvoiceDraft
    @Binding var path: [InvoiceRoute]
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Environment(Toast.self) private var toast
    @State private var showDatePicker = false

    private var store: Store { Store(context: context) }
    private var duplicate: Bool { draft.number.map(store.invoiceExists) ?? false }
    private var canReview: Bool { draft.data != nil && !duplicate }

    var body: some View {
        List {
            Section {
                TrailingFieldRow(label: "Number", text: $draft.numberText, prefix: "#", first: true,
                                 keyboard: .numberPad, width: 90, invalid: draft.number == nil || duplicate)
                Button { withAnimation { showDatePicker.toggle() } } label: {
                    HStack {
                        Text("Date")
                        Spacer()
                        Text(Dates.mdy(draft.date)).monospacedDigit()
                            .foregroundStyle(showDatePicker ? Color.accentInk : Color.inkSecondary)
                    }
                }
                .buttonStyle(RowButtonStyle()).listRowChrome()
                .accessibilityValue(Dates.mdy(draft.date))
                .accessibilityHint("Shows a calendar")
                if showDatePicker {
                    DatePicker("Date", selection: Binding(get: { draft.date }, set: { draft.date = Dates.day($0) }),
                               displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .hairlineCell()
                }
                if duplicate, let n = draft.number {
                    Footnote("Invoice #\(String(n)) already exists.", color: .destructive)
                } else if draft.number == nil {
                    Footnote("Invoice number must be a positive whole number.", color: .destructive)
                }
            } header: { header("Invoice") }

            Section {
                Button { path.append(.contacts) } label: {
                    HStack {
                        Text(draft.contact?.title ?? "Choose contact")
                            .foregroundStyle(draft.contact == nil ? Color.accentInk : Color.ink)
                        Spacer()
                        Chevron()
                    }
                }
                .buttonStyle(RowButtonStyle(first: true)).listRowChrome()
                .accessibilityLabel("Bill to")
                .accessibilityValue(draft.contact?.label ?? "Not chosen")
            } header: { header("Bill to") }

            Section {
                Button { path.append(.addresses) } label: {
                    HStack {
                        Text(draft.address.map(Strings.addressLabel) ?? "Choose job address")
                            .foregroundStyle(draft.address == nil ? Color.accentInk : Color.ink)
                        Spacer()
                        Chevron()
                    }
                }
                .buttonStyle(RowButtonStyle(first: true)).listRowChrome()
                .accessibilityLabel("For, job address")
                .accessibilityValue(draft.address.map(Strings.addressLabel) ?? "Not chosen")
            } header: { header("For") }

            Section {
                ForEach(Array(draft.lines.enumerated()), id: \.offset) { index, line in
                    Button { path.append(.item(index)) } label: {
                        HStack(spacing: 12) {
                            Button { removeLine(index) } label: { MinusBadge() }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(line.description)")
                            Text(line.description).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12)
                            Text(Money.format(line.price)).monospacedDigit()
                        }
                    }
                    .buttonStyle(RowButtonStyle(first: index == 0)).listRowChrome()
                    .accessibilityHint("Edit this line")
                    .swipeActions {
                        Button("Delete", role: .destructive) { removeLine(index) }
                    }
                }
                Button { path.append(.item(nil)) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus").font(.system(size: 18, weight: .light)).frame(width: 22)
                        Text("Add item").font(.barlow(17, FontName.medium))
                    }
                    .foregroundStyle(Color.accentInk)
                }
                .buttonStyle(RowButtonStyle(first: draft.lines.isEmpty)).listRowChrome()
            } header: { header("Line items") }

            Section {
                TrailingFieldRow(label: "Tax rate", text: $draft.taxText, suffix: "%", first: true,
                                 width: 64, invalid: draft.taxRate == nil)
                ValueRow(label: "Subtotal", value: Money.format(draft.totals.subtotal))
                ValueRow(label: "Tax", value: Money.format(draft.totals.tax))
                TotalRow(amount: Money.format(draft.totals.total))
                Footnote(draft.taxRate == nil ? "Tax rate must be between 0 and 100."
                         : draft.missing.isEmpty ? "Cancelling never uses up an invoice number."
                         : "Add \(draft.missing.joined(separator: ", ")) to review.",
                         color: draft.taxRate == nil ? .destructive : .inkSecondary)
                    .padding(.bottom, 24)
            } header: { header("Totals") }
        }
        .industryList()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(draft.isRepeat ? "Repeat invoice" : "New invoice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { cancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Review") { hideKeyboard(); path.append(.review) }
                    .fontWeight(.semibold)
                    .disabled(!canReview)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
            }
        }
    }

    private func removeLine(_ index: Int) {
        guard draft.lines.indices.contains(index) else { return }
        withAnimation { _ = draft.lines.remove(at: index) }
    }

    private func cancel() {
        let next = Store(context: context).business().nextInvoiceNumber
        router.invoiceSheet = nil
        toast.show("Cancelled. #\(next) is still available.")
    }
}
