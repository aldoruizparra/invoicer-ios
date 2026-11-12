import InvoicerKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Paste the weekly email (or lines like "10/07- Acme Homes 123 Main St $65"),
/// or pick an .eml file. Shows what was found before adding anything.
struct ImportEmailView: View {
    let sheet: WeekSheet
    let done: (WeekSheet) -> Void

    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Environment(Toast.self) private var toast
    @State private var text = ""
    @State private var picking = false
    @State private var fileError: String?

    private var store: WeeklyStore { WeeklyStore(context: context) }
    private var parsed: Result<WeeklyLog, Error>? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Result { try WeeklyStore.parse(text, for: sheet) }
    }
    private var log: WeeklyLog? { if case .success(let l)? = parsed { l } else { nil } }
    private var plan: WeeklyStore.ImportPlan? { log.map { store.plan($0, into: sheet) } }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    PasteButton(payloadType: String.self) { strings in
                        if let s = strings.first { Task { @MainActor in text = s } }
                    }
                    .buttonBorderShape(.roundedRectangle(radius: 0))
                    .labelStyle(.titleAndIcon)
                    .tint(.accentFill)
                    .frame(maxWidth: .infinity)
                    Text("Open the email in Mail or Gmail, select all the text, Copy, then tap Paste here.")
                        .footnoteStyle()
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .plainRow(top: 8, bottom: 8, horizontal: 22)
            }

            Section {
                TextEditor(text: $text)
                    .font(.system(.callout, design: .monospaced))
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("…or type lines like\n10/07- Acme Homes 123 Main St $65")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(Color.inkTertiary)
                                .padding(.top, 8).padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("Email text")
                    .hairlineCell(first: true, verticalPadding: 6)
                Button("Choose an .eml file instead") { picking = true }
                    .font(.barlow(15, FontName.medium, relativeTo: .subheadline))
                    .foregroundStyle(Color.accentInk)
                    .plainRow(top: 10)
                if let fileError { Footnote(fileError, color: .destructive) }
            } header: { header("Email text") }

            if let parsed {
                switch parsed {
                case .failure(let error):
                    Section { Footnote(error.localizedDescription, color: .destructive) }
                case .success(let log) where log.jobs.isEmpty:
                    Section {
                        Footnote("No houses found yet. Each one should look like “10/07- Acme Homes 123 Main St $65”.",
                                 color: .warning)
                    }
                case .success(let log):
                    preview(log)
                }
            }
        }
        .industryList()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Paste from email")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { done(sheet) } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { add() }.fontWeight(.semibold).disabled((plan?.addCount ?? 0) == 0)
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { hideKeyboard() } }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.eml, .emailMessage, .plainText, .data]) { r in
            do { load(try r.get()) } catch { fileError = error.localizedDescription }
        }
        .onAppear {
            if let url = router.incomingEmail { router.incomingEmail = nil; load(url) }
        }
    }

    private func preview(_ log: WeeklyLog) -> some View {
        let plan = store.plan(log, into: sheet)
        let parsedTotal = log.parsedTotal
        return Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Found").kickerStyle()
                HStack(alignment: .firstTextBaseline) {
                    Text("\(String(log.jobs.count)) house\(log.jobs.count == 1 ? "" : "s")")
                        .font(.condensed(26, relativeTo: .title2))
                    Spacer()
                    Text(Money.format(parsedTotal)).font(.condensed(26, relativeTo: .title2)).monospacedDigit()
                }
                if let stated = log.statedTotal {
                    Text(stated == parsedTotal ? "✓ Matches the email's Total: \(Money.format(stated))"
                         : "The email says Total: \(Money.format(stated)) — off by \(Money.format(stated - parsedTotal))")
                        .font(.barlow(14, relativeTo: .subheadline))
                        .foregroundStyle(stated == parsedTotal ? Color.accentInk : Color.warning)
                }
                if log.missingCount > 0 {
                    Text("\(String(log.missingCount)) without an amount — you can add them after.")
                        .font(.barlow(14, relativeTo: .subheadline)).foregroundStyle(Color.inkSecondary)
                }
                if let (s, e) = plan.newPeriod {
                    Text("Goes into a new week: \(WeekSheet.label(s, e))")
                        .font(.barlow(14, relativeTo: .subheadline)).foregroundStyle(Color.inkSecondary)
                } else if let s = log.periodStart, let e = log.periodEnd {
                    Text("Week: \(WeekSheet.label(s, e))").font(.barlow(14, relativeTo: .subheadline))
                        .foregroundStyle(Color.inkSecondary)
                }
                if plan.duplicates > 0 {
                    Text("\(String(plan.duplicates)) already in this week — skipped.")
                        .font(.barlow(14, relativeTo: .subheadline)).foregroundStyle(Color.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .blueprint(bordered: true)
            .plainRow(top: 20, bottom: 14, horizontal: 22)

            ForEach(Array(log.jobs.enumerated()), id: \.offset) { i, job in
                HStack(spacing: 12) {
                    let p = Dates.parts(job.date)
                    Text(String(format: "%02d/%02d", p.month, p.day)).font(.barlow(14)).monospacedDigit()
                        .foregroundStyle(Color.inkSecondary).frame(width: 44, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(job.client).font(.barlow(16))
                        Text(job.address).font(.barlow(13, relativeTo: .footnote)).foregroundStyle(Color.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(job.amount.map(Money.format) ?? "—").font(.barlow(16)).monospacedDigit()
                        .foregroundStyle(job.amount == nil ? Color.inkTertiary : Color.ink)
                }
                .padding(.vertical, 8)
                .hairlineCell(first: i == 0, minHeight: 44, fill: job.amount == nil ? .accentTint : .clear)
                .accessibilityElement(children: .combine)
            }

            Button("Add \(String(plan.addCount)) house\(plan.addCount == 1 ? "" : "s")") { add() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(plan.addCount == 0)
                .plainRow(top: 24, bottom: 32, horizontal: 22)
        } header: { header("Check before adding") }
    }

    private func load(_ url: URL) {
        do {
            text = try EmlReader.text(from: readPickedFile(url))
            fileError = nil
        } catch {
            fileError = error.localizedDescription
        }
    }

    private func add() {
        guard let plan, plan.addCount > 0 else { return }
        let target = store.apply(plan, into: sheet)
        toast.show("Added \(plan.addCount) house\(plan.addCount == 1 ? "" : "s") to \(target.label)")
        done(target)
    }
}
