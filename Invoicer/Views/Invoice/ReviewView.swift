import InvoicerKit
import SwiftData
import SwiftUI

/// The CLI's summary step: everything at a glance, then Confirm & Create PDF,
/// Edit a Field, or Cancel. Only Confirm uses up the invoice number.
struct ReviewView: View {
    @Bindable var draft: InvoiceDraft
    let business: Business
    @Binding var path: [InvoiceRoute]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(FileStore.self) private var files
    @Environment(Router.self) private var router
    @Environment(Toast.self) private var toast
    @State private var error: String?

    private var duplicate: Bool { draft.number.map(Store(context: context).invoiceExists) ?? false }

    var body: some View {
        List {
            Section {
                ValueRow(label: "Invoice", value: "#\(draft.numberText) · \(Dates.mdy(draft.date))", first: true)
                ValueRow(label: "Bill to", value: billToText)
                ValueRow(label: "For", value: draft.address.map(Strings.addressLabel) ?? "—")
                if duplicate, let n = draft.number {
                    Footnote("Invoice #\(String(n)) already exists. Use Edit a field to change the number.", color: .destructive)
                }
            } header: { header("Summary") }

            Section {
                ForEach(Array(draft.lines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(line.description).frame(maxWidth: .infinity, alignment: .leading)
                        Text(Money.format(line.price)).monospacedDigit()
                    }
                    .font(.barlow(16))
                    .hairlineCell(first: index == 0, minHeight: 44, verticalPadding: 10)
                    .accessibilityElement(children: .combine)
                }
                SubtotalRows(totals: draft.totals, rate: draft.taxRate ?? 0)
                TotalRow(amount: Money.format(draft.totals.total), size: 26)
                Footnote("Saves \(draft.filename)")
            }
            .listSectionSpacing(12)

            Section {
                VStack(spacing: 12) {
                    Button("Confirm & create PDF", action: confirm)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(draft.data == nil || duplicate)
                    HStack(spacing: 12) {
                        Button("Edit a field") { path.removeAll() }
                            .buttonStyle(SecondaryButtonStyle())
                        Button("Cancel", action: cancel)
                            .buttonStyle(SecondaryButtonStyle(tint: .destructive, pressedFill: .destructiveTint))
                    }
                    Text("Cancelling never uses up an invoice number.")
                        .footnoteStyle()
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 24)
                .plainRow(top: 28, horizontal: 22)
            }
        }
        .industryList()
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
        }
        .alert("Couldn't create the invoice", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private var billToText: String {
        guard let c = draft.contact else { return "—" }
        return ([c.company.isEmpty ? c.attention : c.company] + (c.company.isEmpty ? [] : ["Attn: \(c.attention)"]))
            .joined(separator: "\n")
    }

    private func confirm() {
        guard let data = draft.data else { return }
        do {
            try Store(context: context).finalize(data, files: files)
        } catch {
            self.error = error.localizedDescription
            return
        }
        let pdf = files.pdf(for: data, sender: business.sender)
        router.invoiceSheet = nil
        toast.show("Saved \(data.filename)")
        // Let the sheet finish dismissing before presenting the full-screen preview.
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            router.preview = PreviewItem(filename: data.filename, data: pdf.data, url: pdf.url)
        }
    }

    private func cancel() {
        let next = Store(context: context).business().nextInvoiceNumber
        router.invoiceSheet = nil
        toast.show("Cancelled. #\(next) is still available.")
    }
}

struct SubtotalRows: View {
    let totals: Money.Totals
    let rate: Decimal

    var body: some View {
        VStack(spacing: 2) {
            HStack { Text("Subtotal"); Spacer(); Text(Money.format(totals.subtotal)).monospacedDigit() }
            HStack { Text("Tax (\(Money.formatRate(rate))%)"); Spacer(); Text(Money.format(totals.tax)).monospacedDigit() }
        }
        .font(.barlow(15, relativeTo: .subheadline))
        .foregroundStyle(Color.inkSecondary)
        .hairlineCell(minHeight: 60, verticalPadding: 8)
        .accessibilityElement(children: .combine)
    }
}
