import InvoicerKit
import SwiftData
import SwiftUI

/// Saved tab (= `invoice.py list`): contacts, job addresses and items, most
/// recently used first. Edit mode deletes; tapping a row edits it.
struct SavedView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case contacts = "Contacts", addresses = "Addresses", items = "Items"
        var id: String { rawValue }
    }

    enum Editing: Identifiable {
        case contact(Contact), address(JobAddress), item(SavedItem)
        var id: PersistentIdentifier {
            switch self {
            case .contact(let c): c.persistentModelID
            case .address(let a): a.persistentModelID
            case .item(let i): i.persistentModelID
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Contact.lastUsed, order: .reverse)]) private var contacts: [Contact]
    @Query(sort: [SortDescriptor(\JobAddress.lastUsed, order: .reverse)]) private var addresses: [JobAddress]
    @Query(sort: [SortDescriptor(\SavedItem.lastUsed, order: .reverse)]) private var items: [SavedItem]
    @Query private var invoices: [Invoice]
    @State private var kind: Kind = .contacts
    @State private var editMode: EditMode = .inactive
    @State private var editing: Editing?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Show", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.rawValue.uppercased()).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .plainRow(top: 0, bottom: 18)
                }

                Section {
                    switch kind {
                    case .contacts:
                        ForEach(Array(contacts.enumerated()), id: \.element.id) { i, c in
                            row(first: i == 0, title: c.info.title, subtitle: c.info.subtitle) { editing = .contact(c) }
                        }
                        .onDelete { delete(contacts, $0) }
                        if contacts.isEmpty { empty("No saved contacts yet.") }
                    case .addresses:
                        ForEach(Array(addresses.enumerated()), id: \.element.id) { i, a in
                            let n = invoices.filter { Strings.norm($0.jobAddress) == Strings.norm(a.text) }.count
                            row(first: i == 0, title: a.label, subtitle: "\(n) invoice\(n == 1 ? "" : "s")") {
                                editing = .address(a)
                            }
                        }
                        .onDelete { delete(addresses, $0) }
                        if addresses.isEmpty { empty("No saved job addresses yet.") }
                    case .items:
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            row(first: i == 0, title: item.itemDescription, subtitle: "Last price used",
                                trailing: Money.format(item.lastPrice)) { editing = .item(item) }
                        }
                        .onDelete { delete(items, $0) }
                        if items.isEmpty { empty("No saved items yet.") }
                    }
                    Footnote("Most recently used first. New entries are saved as soon as you add them on an invoice.")
                }
            }
            .industryList()
            .environment(\.editMode, $editMode)
            .navigationTitle("Saved")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode.isEditing ? "Done" : "Edit") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .fontWeight(editMode.isEditing ? .semibold : .regular)
                }
            }
            .onChange(of: kind) { editMode = .inactive }
            .sheet(item: $editing) { target in
                NavigationStack { editor(for: target) }.tint(.accentInk)
            }
        }
    }

    private func row(first: Bool, title: String, subtitle: String, trailing: String = "",
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                TwoLineLabel(title: title, subtitle: subtitle)
                if !trailing.isEmpty {
                    Text(trailing).monospacedDigit().foregroundStyle(Color.inkSecondary)
                }
            }
        }
        .buttonStyle(RowButtonStyle(first: first)).listRowChrome()
        .accessibilityHint("Edit")
    }

    private func empty(_ text: String) -> some View {
        Text(text).foregroundStyle(Color.inkSecondary).hairlineCell(first: true)
    }

    private func delete<T: PersistentModel>(_ list: [T], _ offsets: IndexSet) {
        for i in offsets { context.delete(list[i]) }
        try? context.save()
    }

    @ViewBuilder
    private func editor(for target: Editing) -> some View {
        let store = Store(context: context)
        switch target {
        case .contact(let c):
            ContactEditorView(title: "Edit contact", initial: c.info) { info in
                store.updateContact(c, to: info); editing = nil
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = nil } } }
        case .address(let a):
            AddressEditorView(title: "Edit job address", initial: a.text) { text in
                store.updateAddress(a, to: text); editing = nil
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = nil } } }
        case .item(let item):
            ItemEditorView(item: item) { desc, price in
                store.updateItem(item, description: desc, price: price); editing = nil
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = nil } } }
        }
    }
}

/// Edit a saved item's description and last price.
struct ItemEditorView: View {
    let onSave: (String, Decimal) -> Void
    @State private var desc: String
    @State private var priceText: String

    init(item: SavedItem, onSave: @escaping (String, Decimal) -> Void) {
        self.onSave = onSave
        _desc = State(initialValue: item.itemDescription)
        _priceText = State(initialValue: Money.plain(item.lastPrice))
    }

    private var price: Decimal? { try? Money.parse(priceText) }

    var body: some View {
        List {
            Section {
                FieldRow(label: "Description", text: $desc, first: true, capitalization: .sentences, labelWidth: 104)
                TrailingFieldRow(label: "Last price", text: $priceText, prefix: "$", width: 110, invalid: price == nil)
            } header: { header("Saved item") }
        }
        .industryList()
        .navigationTitle("Edit item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { if let price { onSave(desc.trimmingCharacters(in: .whitespaces), price) } }
                    .fontWeight(.semibold)
                    .disabled(price == nil || desc.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
