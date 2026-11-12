import InvoicerKit
import SwiftData
import SwiftUI

/// Invoices tab: "Repeat last invoice" card (= `invoice.py repeat`) and history.
struct InvoicesView: View {
    let business: Business
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Environment(FileStore.self) private var files
    @Query(sort: [SortDescriptor(\Invoice.createdAt, order: .reverse)]) private var invoices: [Invoice]

    var body: some View {
        NavigationStack {
            List {
                if let last = invoices.first {
                    Section {
                        RepeatCard(last: last, nextNumber: business.nextInvoiceNumber) {
                            router.invoiceSheet = InvoiceDraft(repeating: last.data, business: business)
                        }
                        .plainRow(top: 16, bottom: 10, horizontal: 22)
                    }
                }

                Section {
                    if invoices.isEmpty {
                        VStack(spacing: 16) {
                            Text("No invoices yet").font(.condensed(24, relativeTo: .title2))
                            Text("Create your first invoice. Contacts, job addresses and items you add are saved for next time.")
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Color.inkSecondary)
                            Button("New invoice", action: newInvoice)
                                .buttonStyle(PrimaryButtonStyle())
                                .padding(.horizontal, 6)
                                .padding(.top, 8)
                        }
                        .padding(.vertical, 28)
                        .plainRow(horizontal: 22)
                    } else {
                        ForEach(Array(invoices.enumerated()), id: \.element.id) { index, invoice in
                            Button { open(invoice) } label: {
                                HStack(spacing: 12) {
                                    TwoLineLabel(title: invoice.billTo.title,
                                                 subtitle: "#\(String(invoice.number)) · \(Dates.mdy(invoice.date))")
                                    Text(Money.format(invoice.total))
                                        .font(.barlow(17, FontName.medium))
                                        .monospacedDigit()
                                    Chevron()
                                }
                            }
                            .buttonStyle(RowButtonStyle(first: index == 0)).listRowChrome()
                            .accessibilityLabel("Invoice \(invoice.number), \(invoice.billTo.title), \(Dates.mdy(invoice.date)), \(Money.format(invoice.total))")
                            .accessibilityHint("Opens the PDF")
                        }
                    }
                } header: {
                    if !invoices.isEmpty { header("History") }
                }
            }
            .industryList()
            .navigationTitle("Invoices")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: newInvoice) { Image(systemName: "plus") }
                        .buttonStyle(SquareIconButtonStyle())
                        .accessibilityLabel("New invoice")
                }
            }
        }
    }

    private func newInvoice() {
        router.invoiceSheet = InvoiceDraft(business: business)
    }

    private func open(_ invoice: Invoice) {
        let data = invoice.data
        let pdf = files.pdf(for: data, sender: business.sender)
        router.preview = PreviewItem(filename: data.filename, data: pdf.data, url: pdf.url)
    }
}

/// The Repeat card: last invoice's client and total, and "Repeat as #N · Today".
struct RepeatCard: View {
    let last: Invoice
    let nextNumber: Int
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Repeat last · #\(String(last.number))").kickerStyle()
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(last.billTo.title).font(.condensed(24, relativeTo: .title2))
                    Spacer(minLength: 8)
                    Text(Money.format(last.total)).font(.condensed(24, relativeTo: .title2)).monospacedDigit()
                }
                Text(last.lines.map(\.description).joined(separator: " · "))
                    .font(.barlow(15, relativeTo: .subheadline))
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(2)
                Text("New number #\(String(nextNumber)) · \(Dates.mdy(Date()))")
                    .font(.barlow(13, relativeTo: .footnote))
                    .foregroundStyle(Color.inkSecondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            Button("Repeat as #\(String(nextNumber)) · Today", action: action)
                .buttonStyle(PrimaryButtonStyle(height: 48, marks: false))
                .accessibilityHint("Opens the review with the same client, address and items")
        }
        .padding(18)
        .blueprint(bordered: true)
    }
}
