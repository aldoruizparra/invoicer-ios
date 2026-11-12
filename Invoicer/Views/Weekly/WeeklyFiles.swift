import InvoicerKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct WeeklyResult: Identifiable {
    struct File: Identifiable {
        var id: String { name }
        let name: String
        let data: Data
        let type: UTType
    }
    let id = UUID()
    let files: [File]
    let location: String
}

/// After creating: share or save each file, like invoices.
struct WeeklyResultView: View {
    let result: WeeklyResult
    @Environment(\.dismiss) private var dismiss
    @Environment(FileStore.self) private var files
    @State private var exporting: WeeklyResult.File?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(result.files.enumerated()), id: \.element.id) { index, file in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(file.name).font(.barlow(16, FontName.medium)).lineLimit(2)
                            HStack(spacing: 12) {
                                if let url = files.temporaryCopy(file.data, named: file.name) {
                                    ShareLink(item: url) { Text("Share") }
                                        .buttonStyle(PrimaryButtonStyle(height: 40, marks: false))
                                }
                                Button("Save to Files") { exporting = file }
                                    .buttonStyle(SecondaryButtonStyle(height: 40))
                            }
                        }
                        .hairlineCell(first: index == 0, verticalPadding: 14)
                    }
                    Footnote("Also saved in \(result.location).")
                } header: { header("Created") }
            }
            .industryList()
            .navigationTitle("Weekly invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileExporter(isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
                          document: exporting.map { ExportFile(data: $0.data, type: $0.type) },
                          contentType: exporting?.type ?? .data,
                          defaultFilename: exporting?.name) { _ in }
        }
        .tint(.accentInk)
        .presentationDetents([.medium, .large])
    }
}

/// First run (= `invoice.py setup-weekly`): contractor info and the client's blank
/// .xlsx template, kept privately in the app. Editable later.
struct WeeklySetupView: View {
    let business: Business
    let suggestion: Contractor?
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(FileStore.self) private var files
    @State private var c = Contractor()
    @State private var picking = false
    @State private var templateError: String?

    init(business: Business, suggestion: Contractor?, onDone: (() -> Void)? = nil) {
        self.business = business
        self.suggestion = suggestion
        self.onDone = onDone
    }

    private var canSave: Bool { !c.name.trimmingCharacters(in: .whitespaces).isEmpty && files.hasTemplate }

    var body: some View {
        List {
            Section {
                FieldRow(label: "Name", text: $c.name, placeholder: "Required", first: true, contentType: .name)
                FieldRow(label: "Street", text: $c.street, contentType: .streetAddressLine1)
                FieldRow(label: "Address 2", text: $c.address2, placeholder: "Optional", contentType: .streetAddressLine2)
                FieldRow(label: "City", text: $c.cityStateZip, placeholder: "City, ST 12345",
                         contentType: .addressCityAndState)
                FieldRow(label: "Email", text: $c.email, keyboard: .emailAddress, contentType: .emailAddress,
                         capitalization: .never)
                FieldRow(label: "Phone", text: $c.phone, keyboard: .phonePad, contentType: .telephoneNumber)
            } header: { header("Contractor") }

            Section {
                Button { picking = true } label: {
                    HStack {
                        Text("Blank template")
                        Spacer()
                        Text(files.hasTemplate ? (business.templateName.isEmpty ? "Saved" : business.templateName)
                             : "Choose .xlsx")
                            .foregroundStyle(files.hasTemplate ? Color.inkSecondary : Color.accentInk)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(RowButtonStyle(first: true)).listRowChrome()
                if let templateError { Footnote(templateError, color: .destructive) }
                Footnote(files.hasTemplate ? "A private copy is kept in the app. Choose another file to replace it."
                         : "The client's blank “Weekly Invoice Sheet” workbook. A private copy is kept in the app.")
            } header: { header("Template") }
        }
        .industryList()
        .navigationTitle("Weekly setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if onDone != nil {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).fontWeight(.semibold).disabled(!canSave)
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.xlsx]) { r in
            do {
                let url = try r.get()
                try files.saveTemplate(readPickedFile(url))
                business.templateName = url.lastPathComponent
                templateError = nil
            } catch {
                templateError = "Can't use that file: \(error.localizedDescription)"
            }
        }
        .onAppear {
            c = business.contractor
            if let s = suggestion {
                if c.name.isEmpty { c.name = s.name }
                if c.street.isEmpty { c.street = s.street }
                if c.cityStateZip.isEmpty { c.cityStateZip = s.cityStateZip }
            }
        }
    }

    private func save() {
        func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
        business.contractor = Contractor(name: t(c.name), street: t(c.street), address2: t(c.address2),
                                         cityStateZip: t(c.cityStateZip), email: t(c.email), phone: t(c.phone))
        if let onDone { onDone() } else { dismiss() }
    }
}
