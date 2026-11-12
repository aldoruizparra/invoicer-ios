import InvoicerKit
import SwiftData
import SwiftUI

/// Bill to: searchable saved contacts, most recent first. Typing a name that
/// isn't saved offers `Add "<text>"`.
struct ContactPickerView: View {
    @Bindable var draft: InvoiceDraft
    @Binding var path: [InvoiceRoute]
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Contact.lastUsed, order: .reverse)]) private var contacts: [Contact]
    @State private var query = ""

    private var q: String { query.trimmingCharacters(in: .whitespaces) }
    private var matches: [Contact] {
        guard !q.isEmpty else { return contacts }
        return contacts.filter { c in
            [c.attention, c.attention2, c.company, c.street, c.cityState].contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }
    private var exactMatch: Bool {
        contacts.contains { $0.info.title.caseInsensitiveCompare(q) == .orderedSame
            || $0.attention.caseInsensitiveCompare(q) == .orderedSame }
    }

    var body: some View {
        List {
            Section {
                if !q.isEmpty && !exactMatch {
                    AddRow(text: "Add “\(q)”", first: true) { path.append(.newContact(q)) }
                } else if q.isEmpty {
                    AddRow(text: "New contact", first: true) { path.append(.newContact("")) }
                }
                ForEach(matches) { contact in
                    Button { choose(contact) } label: {
                        HStack {
                            TwoLineLabel(title: contact.info.title, subtitle: contact.info.subtitle)
                            if draft.contact?.key == contact.info.key {
                                Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Color.accentInk)
                                    .accessibilityLabel("Selected")
                            }
                        }
                    }
                    .buttonStyle(RowButtonStyle()).listRowChrome()
                    .swipeActions {
                        Button("Delete", role: .destructive) { context.delete(contact) }
                        Button("Edit") { path.append(.editContact(contact.persistentModelID)) }.tint(.accentFill)
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { path.append(.editContact(contact.persistentModelID)) }
                        Button("Remove", systemImage: "trash", role: .destructive) { context.delete(contact) }
                    }
                }
                Footnote("New entries are saved as soon as you add them. Swipe left on one to edit or remove it.")
            } header: { header("Recent") }
        }
        .industryList()
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search or add a contact")
        .onSubmit(of: .search) { if !q.isEmpty && !exactMatch { path.append(.newContact(q)) } }
        .navigationTitle("Bill to")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choose(_ contact: Contact) {
        draft.contact = contact.info
        path.removeLast()
    }
}

/// For: searchable saved job addresses, most recent first.
struct AddressPickerView: View {
    @Bindable var draft: InvoiceDraft
    @Binding var path: [InvoiceRoute]
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\JobAddress.lastUsed, order: .reverse)]) private var addresses: [JobAddress]
    @Query private var invoices: [Invoice]
    @State private var query = ""

    private var q: String { query.trimmingCharacters(in: .whitespaces) }
    private var matches: [JobAddress] {
        q.isEmpty ? addresses : addresses.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }
    private var exactMatch: Bool {
        addresses.contains { a in
            a.label.caseInsensitiveCompare(q) == .orderedSame
                || (a.text.split(separator: "\n").first.map { $0.caseInsensitiveCompare(q) == .orderedSame } ?? false)
        }
    }

    var body: some View {
        List {
            Section {
                if !q.isEmpty && !exactMatch {
                    AddRow(text: "Add “\(q)”", first: true) { path.append(.newAddress(q)) }
                } else if q.isEmpty {
                    AddRow(text: "New job address", first: true) { path.append(.newAddress("")) }
                }
                ForEach(matches) { address in
                    let count = invoices.filter { Strings.norm($0.jobAddress) == Strings.norm(address.text) }.count
                    Button { choose(address) } label: {
                        HStack {
                            TwoLineLabel(title: address.label, subtitle: "\(count) invoice\(count == 1 ? "" : "s")")
                            if draft.address.map(Strings.norm) == Strings.norm(address.text) {
                                Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Color.accentInk)
                                    .accessibilityLabel("Selected")
                            }
                        }
                    }
                    .buttonStyle(RowButtonStyle()).listRowChrome()
                    .swipeActions {
                        Button("Delete", role: .destructive) { context.delete(address) }
                    }
                }
                Footnote("New entries are saved as soon as you add them.")
            } header: { header("Recent") }
        }
        .industryList()
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search or add a job address")
        .onSubmit(of: .search) { if !q.isEmpty && !exactMatch { path.append(.newAddress(q)) } }
        .navigationTitle("For")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choose(_ address: JobAddress) {
        draft.address = address.text
        path.removeLast()
    }
}

/// "+ Add …" row in accent.
struct AddRow: View {
    let text: String
    var first = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus").font(.system(size: 18, weight: .light)).frame(width: 22)
                Text(text).font(.barlow(17, FontName.medium))
            }
            .foregroundStyle(Color.accentInk)
        }
        .buttonStyle(RowButtonStyle(first: first)).listRowChrome()
    }
}

// MARK: - editors

/// A bill-to contact's fields, like the CLI's `new_contact`. Attention is required.
struct ContactEditorView: View {
    let title: String
    let initial: ContactInfo
    let onSave: (ContactInfo) -> Void

    @State private var info: ContactInfo
    @FocusState private var focus: Int?

    init(title: String, initial: ContactInfo, onSave: @escaping (ContactInfo) -> Void) {
        self.title = title
        self.initial = initial
        self.onSave = onSave
        _info = State(initialValue: initial)
    }

    private var zipError: String? {
        do { _ = try Validate.zip(info.zip); return nil } catch { return error.localizedDescription }
    }
    private var canSave: Bool { !info.attention.trimmingCharacters(in: .whitespaces).isEmpty && zipError == nil }

    var body: some View {
        List {
            Section {
                FieldRow(label: "Attention", text: $info.attention, placeholder: "Name (required)", first: true,
                         contentType: .name, labelWidth: 104)
                    .focused($focus, equals: 0)
                FieldRow(label: "Second", text: $info.attention2, placeholder: "Second contact (optional)",
                         labelWidth: 104)
                FieldRow(label: "Company", text: $info.company, placeholder: "Optional",
                         contentType: .organizationName, labelWidth: 104)
            } header: { header("Contact") }
            Section {
                FieldRow(label: "Street", text: $info.street, placeholder: "456 Oak Ave", first: true,
                         contentType: .streetAddressLine1, labelWidth: 104)
                FieldRow(label: "City, State", text: $info.cityState, placeholder: "Plano, TX",
                         contentType: .addressCityAndState, labelWidth: 104)
                FieldRow(label: "ZIP", text: $info.zip, placeholder: "Optional", keyboard: .numbersAndPunctuation,
                         contentType: .postalCode, labelWidth: 104, invalid: zipError != nil)
                if let zipError { Footnote(zipError, color: .destructive) }
            } header: { header("Address") }
        }
        .industryList()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { onSave(trimmed(info)) }.fontWeight(.semibold).disabled(!canSave)
            }
        }
        .onAppear { if initial.attention.isEmpty { focus = 0 } }
    }

    private func trimmed(_ c: ContactInfo) -> ContactInfo {
        func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
        return ContactInfo(attention: t(c.attention), attention2: t(c.attention2), company: t(c.company),
                           street: t(c.street), cityState: t(c.cityState), zip: t(c.zip))
    }
}

/// Job address: street (required), then an optional city line and ZIP. Stored as
/// "street\ncity, state zip" like the CLI.
struct AddressEditorView: View {
    let title: String
    let onSave: (String) -> Void
    @State private var street: String
    @State private var cityState: String
    @State private var zip: String
    @FocusState private var focused: Bool

    /// `initial` may be a typed street or a stored two-line address.
    init(title: String, initial: String, onSave: @escaping (String) -> Void) {
        self.title = title
        self.onSave = onSave
        let parts = initial.split(separator: "\n", maxSplits: 1).map(String.init)
        _street = State(initialValue: parts.first ?? "")
        var city = parts.count > 1 ? parts[1] : ""
        var zipCode = ""
        if let r = city.range(of: #"\s*\d{5}(-\d{4})?$"#, options: .regularExpression) {
            zipCode = city[r].trimmingCharacters(in: .whitespaces)
            city.removeSubrange(r)
        }
        _cityState = State(initialValue: city)
        _zip = State(initialValue: zipCode)
    }

    private var zipError: String? {
        do { _ = try Validate.zip(zip); return nil } catch { return error.localizedDescription }
    }
    private var canSave: Bool { !street.trimmingCharacters(in: .whitespaces).isEmpty && zipError == nil }

    var body: some View {
        List {
            Section {
                FieldRow(label: "Street", text: $street, placeholder: "Required", first: true,
                         contentType: .streetAddressLine1, labelWidth: 104)
                    .focused($focused)
                FieldRow(label: "City, State", text: $cityState, placeholder: "Optional",
                         contentType: .addressCityAndState, labelWidth: 104)
                FieldRow(label: "ZIP", text: $zip, placeholder: "Optional", keyboard: .numbersAndPunctuation,
                         contentType: .postalCode, labelWidth: 104, invalid: zipError != nil)
                if let zipError { Footnote(zipError, color: .destructive) }
            } header: { header("Job address") }
        }
        .industryList()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(Strings.jobAddress(street: street, cityState: cityState, zip: zip))
                }
                .fontWeight(.semibold).disabled(!canSave)
            }
        }
        .onAppear { if street.isEmpty { focused = true } }
    }
}

/// Edit a saved contact by id (from the Bill to list or the Saved tab).
struct EditSavedContact: View {
    let id: PersistentIdentifier
    /// (old, new)
    let onSave: (ContactInfo, ContactInfo) -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        if let contact = context.model(for: id) as? Contact {
            ContactEditorView(title: "Edit contact", initial: contact.info) { info in
                let old = contact.info
                Store(context: context).updateContact(contact, to: info)
                onSave(old, info)
            }
        }
    }
}
