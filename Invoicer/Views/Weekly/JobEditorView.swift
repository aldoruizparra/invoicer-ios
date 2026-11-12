import InvoicerKit
import SwiftData
import SwiftUI

/// Add or edit one house: pick the day, the client, the address and the amount.
/// Recent clients, that client's addresses and the last price are one tap away,
/// and "Save & add another" keeps the day and client for the next house.
struct JobEditorView: View {
    let sheet: WeekSheet
    let target: WeeklyHomeView.JobTarget

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var day = Date()
    @State private var client = ""
    @State private var address = ""
    @State private var amountText = ""
    @State private var added: [String] = []
    @State private var confirmDelete = false
    @FocusState private var focus: Field?

    enum Field { case client, address, amount }

    private var store: WeeklyStore { WeeklyStore(context: context) }
    private var editingJob: WorkJob? { if case .edit(let j) = target { j } else { nil } }
    private var amount: Decimal? { try? Money.parse(amountText) }
    private var amountInvalid: Bool { !amountText.trimmingCharacters(in: .whitespaces).isEmpty && amount == nil }
    private var canSave: Bool {
        !(client.trimmingCharacters(in: .whitespaces).isEmpty && address.trimmingCharacters(in: .whitespaces).isEmpty)
            && !amountInvalid
    }

    private var clientSuggestions: [String] {
        let q = client.trimmingCharacters(in: .whitespaces)
        let all = store.recentClients(limit: 12)
        let list = q.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(q) && Strings.norm($0) != Strings.norm(q) }
        return Array(list.prefix(6))
    }
    private var addressSuggestions: [String] {
        let q = address.trimmingCharacters(in: .whitespaces)
        let all = store.addresses(for: client, limit: 12)
        let list = q.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(q) && Strings.norm($0) != Strings.norm(q) }
        return Array(list.prefix(6))
    }
    private var lastAmount: Decimal? { store.lastAmount(client: client, address: address) }

    var body: some View {
        List {
            Section {
                Group {
                    if sheet.days.count <= 8 {
                        // The whole week fits: chips share the width.
                        HStack(spacing: 6) {
                            ForEach(sheet.days, id: \.self) { d in
                                DayChip(day: d, selected: Dates.day(d) == Dates.day(day)) { day = d }
                            }
                        }
                        .padding(.horizontal, 16)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(sheet.days, id: \.self) { d in
                                        DayChip(day: d, selected: Dates.day(d) == Dates.day(day)) { day = d }
                                            .frame(width: 52)
                                            .id(d)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                            .onAppear { proxy.scrollTo(Dates.day(day), anchor: .center) }
                        }
                    }
                }
                .plainRow(horizontal: 0)
            } header: { header("Day") }

            Section {
                TextField("Client, e.g. Acme Homes", text: $client)
                    .focused($focus, equals: .client)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .onSubmit { focus = .address }
                    .accessibilityLabel("Client")
                    .hairlineCell(first: true)
                if !clientSuggestions.isEmpty {
                    SuggestionChips(values: clientSuggestions) { value in
                        client = value
                        focus = .address
                    }
                    .plainRow(top: 10)
                }
            } header: { header("Client") }

            Section {
                TextField("Street address, e.g. 123 Main St", text: $address)
                    .focused($focus, equals: .address)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .onSubmit { fillAmountIfEmpty(); focus = .amount }
                    .accessibilityLabel("House address")
                    .hairlineCell(first: true)
                if !addressSuggestions.isEmpty {
                    SuggestionChips(values: addressSuggestions) { value in
                        address = value
                        fillAmountIfEmpty()
                        focus = .amount
                    }
                    .plainRow(top: 10)
                }
            } header: { header("House address") }

            Section {
                HStack(spacing: 4) {
                    Text("Amount")
                    Spacer()
                    Text("$").foregroundStyle(Color.inkSecondary)
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(maxWidth: 120)
                        .focused($focus, equals: .amount)
                        .foregroundStyle(amountInvalid ? Color.destructive : Color.ink)
                        .accessibilityLabel("Amount in dollars")
                }
                .hairlineCell(first: true)
                if let lastAmount, amount != lastAmount {
                    SuggestionChips(values: ["Last time \(Money.format(lastAmount))"]) { _ in
                        amountText = Money.plain(lastAmount)
                    }
                    .plainRow(top: 10)
                }
                Footnote(amountInvalid ? "Enter an amount like 65 or 65.50." : "Leave it blank if you don't know it yet.",
                         color: amountInvalid ? .destructive : .inkSecondary)
            } header: { header("Amount") }

            Section {
                VStack(spacing: 12) {
                    if editingJob == nil {
                        Button("Save & add another") { save(another: true) }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!canSave)
                        Button("Save & close") { save(another: false) }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(!canSave)
                    } else {
                        Button("Save") { save(another: false) }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!canSave)
                        Button("Delete this house") { confirmDelete = true }
                            .buttonStyle(SecondaryButtonStyle(tint: .destructive, pressedFill: .destructiveTint))
                    }
                }
                .plainRow(top: 24, bottom: 12, horizontal: 22)
                if !added.isEmpty {
                    Text("Added: " + added.joined(separator: " · "))
                        .footnoteStyle()
                        .plainRow(bottom: 24, horizontal: 22)
                }
            }
        }
        .industryList()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(editingJob == nil ? "Add a house" : "Edit house")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(added.isEmpty ? "Cancel" : "Done") { dismiss() }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                if focus == .amount {
                    Button(editingJob == nil ? "Save & add another" : "Save") { save(another: editingJob == nil) }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                } else {
                    Button("Done") { hideKeyboard() }
                }
            }
        }
        .confirmationDialog("Delete this house?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let job = editingJob { context.delete(job); try? context.save() }
                dismiss()
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        switch target {
        case .edit(let job):
            day = job.date; client = job.client; address = job.address
            amountText = job.amount.map(Money.plain) ?? ""
        case .new(let preset):
            if let preset {
                day = preset
            } else if let last = store.jobs(in: sheet).max(by: { $0.createdAt < $1.createdAt }) {
                day = last.date   // keep logging on the same day
            } else {
                let today = Dates.day(Date())
                day = sheet.days.contains(today) ? today : (sheet.days.first ?? today)
            }
            focus = .client
        }
    }

    private func fillAmountIfEmpty() {
        if amountText.isEmpty, let lastAmount { amountText = Money.plain(lastAmount) }
    }

    private func save(another: Bool) {
        guard canSave else { return }
        let value = amountText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : amount
        if let job = editingJob {
            job.date = Dates.day(day)
            job.client = client.trimmingCharacters(in: .whitespaces)
            job.address = address.trimmingCharacters(in: .whitespaces)
            job.amount = value
            try? context.save()
            dismiss()
            return
        }
        store.addJob(to: sheet, date: day, client: client, address: address, amount: value)
        if another {
            added.append(address.isEmpty ? client : address)
            address = ""
            amountText = ""
            focus = .address
        } else {
            dismiss()
        }
    }
}

/// A big square day button: "TUE" over "07".
struct DayChip: View {
    let day: Date
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let cal = Dates.calendar
        let weekday = cal.shortWeekdaySymbols[cal.component(.weekday, from: day) - 1]
        let p = Dates.parts(day)
        Button(action: action) {
            VStack(spacing: 2) {
                Text(weekday).font(.condensed(13, relativeTo: .caption)).tracking(13 * 0.06).textCase(.uppercase)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(String(format: "%02d", p.day)).font(.condensed(24, relativeTo: .title2)).monospacedDigit()
            }
            .foregroundStyle(selected ? Color.white : Color.ink)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(selected ? Color.accentFill : Color.clear)
            .overlay(Rectangle().strokeBorder(selected ? Color.accentFill : Color.divider, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(cal.weekdaySymbols[cal.component(.weekday, from: day) - 1]) \(String(format: "%02d/%02d", p.month, p.day))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Tappable suggestions that wrap onto several lines.
struct SuggestionChips: View {
    let values: [String]
    let pick: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(values, id: \.self) { value in
                Button { pick(value) } label: {
                    Text(value)
                        .font(.barlow(15, FontName.medium, relativeTo: .subheadline))
                        .foregroundStyle(Color.accentInk)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(Color.accentTint)
                        .overlay(Rectangle().strokeBorder(Color.accentSteel.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Fills this in")
            }
        }
    }
}

/// Left-to-right wrapping layout.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
