import InvoicerKit
import SwiftData
import SwiftUI

/// Add or edit a line. The description live-suggests saved items; picking one
/// fills the description and its last price. When adding, the page stays open
/// for the next item; Return on a blank description finishes.
struct LineItemView: View {
    @Bindable var draft: InvoiceDraft
    let editing: Int?
    let done: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\SavedItem.lastUsed, order: .reverse)]) private var saved: [SavedItem]
    @State private var desc = ""
    @State private var priceText = ""
    @State private var added: [LineItem] = []
    @FocusState private var focus: Field?

    enum Field { case desc, price }

    private var price: Decimal? { try? Money.parse(priceText) }
    private var priceError: String? {
        guard !priceText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        do { _ = try Money.parse(priceText); return nil } catch { return error.localizedDescription }
    }
    private var canSave: Bool { !desc.trimmingCharacters(in: .whitespaces).isEmpty && price != nil }
    private var suggestions: [SavedItem] {
        let q = desc.trimmingCharacters(in: .whitespaces)
        let list = q.isEmpty ? saved : saved.filter {
            $0.itemDescription.localizedCaseInsensitiveContains(q)
                && Strings.norm($0.itemDescription) != Strings.norm(q)
        }
        return Array(list.prefix(6))
    }

    var body: some View {
        List {
            Section {
                TextField("Description — start typing", text: $desc)
                    .focused($focus, equals: .desc)
                    .submitLabel(.next)
                    .onSubmit(submitDescription)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityLabel("Description")
                    .hairlineCell(first: true)
                HStack(spacing: 4) {
                    Text("Price")
                    Spacer()
                    Text("$").foregroundStyle(Color.inkSecondary)
                    TextField("0.00", text: $priceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(maxWidth: 110)
                        .focused($focus, equals: .price)
                        .foregroundStyle(priceError == nil ? Color.inkSecondary : Color.destructive)
                        .accessibilityLabel("Price in dollars")
                }
                .hairlineCell()
                if let priceError { Footnote(priceError, color: .destructive) }
            } header: { header("Line item") }

            if !suggestions.isEmpty {
                Section {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, item in
                        Button { pick(item) } label: {
                            HStack {
                                Text(item.itemDescription).font(.barlow(16)).frame(maxWidth: .infinity, alignment: .leading)
                                Text(Money.format(item.lastPrice)).font(.barlow(16)).monospacedDigit()
                                    .foregroundStyle(Color.inkSecondary)
                            }
                        }
                        .buttonStyle(RowButtonStyle(first: index == 0, minHeight: 46)).listRowChrome()
                        .accessibilityLabel("\(item.itemDescription), last price \(Money.format(item.lastPrice))")
                        .accessibilityHint("Fills in the description and price")
                    }
                    Footnote("Picking a saved item fills in the last price you used.")
                } header: { header("Saved items · last price") }
            }

            if editing == nil && !added.isEmpty {
                Section {
                    ForEach(Array(added.enumerated()), id: \.offset) { index, line in
                        HStack {
                            Text(line.description).frame(maxWidth: .infinity, alignment: .leading)
                            Text(Money.format(line.price)).monospacedDigit()
                        }
                        .hairlineCell(first: index == 0, minHeight: 44)
                        .foregroundStyle(Color.inkSecondary)
                    }
                    Footnote("Press Return on an empty description to finish.")
                } header: { header("Added · \(added.count)") }
            }
        }
        .industryList()
        .navigationTitle(editing == nil ? "Add item" : "Edit item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(editing == nil ? "Add" : "Save", action: save)
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
            ToolbarItemGroup(placement: .keyboard) {
                if focus == .price {
                    Button("Description") { focus = .desc }
                    Spacer()
                    Button(editing == nil ? "Add item" : "Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .onAppear {
            if let editing, draft.lines.indices.contains(editing) {
                desc = draft.lines[editing].description
                priceText = Money.plain(draft.lines[editing].price)
            }
            focus = .desc
        }
    }

    private func pick(_ item: SavedItem) {
        desc = item.itemDescription
        priceText = Money.plain(item.lastPrice)
        focus = .price
    }

    /// Return on the description: blank finishes; a saved match prefills its price.
    private func submitDescription() {
        let text = desc.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { done(); return }
        if let match = Store(context: context).findItem(text) {
            desc = match.itemDescription
            if priceText.isEmpty { priceText = Money.plain(match.lastPrice) }
        }
        focus = .price
    }

    private func save() {
        guard let price else { return }
        let text = desc.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let line = LineItem(description: text, price: price)
        // Saving a line remembers it with this price, most recent first.
        Store(context: context).saveItem(text, price: price)
        if let editing, draft.lines.indices.contains(editing) {
            draft.lines[editing] = line
            done()
        } else {
            draft.lines.append(line)
            added.append(line)
            desc = ""
            priceText = ""
            focus = .desc
        }
    }
}
