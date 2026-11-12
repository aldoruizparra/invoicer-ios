import InvoicerKit
import SwiftData
import SwiftUI

/// Weekly tab: the contractor sheet for the client's .xlsx template. Separate
/// from Invoices: log each house as you go (or paste the weekly email), then
/// create the client's spreadsheet at the end of the week.
struct WeeklyHomeView: View {
    let business: Business

    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Environment(FileStore.self) private var files
    @Environment(Toast.self) private var toast
    @Query(sort: [SortDescriptor(\WeekSheet.start, order: .reverse), SortDescriptor(\WeekSheet.createdAt, order: .reverse)])
    private var sheets: [WeekSheet]
    @Query(sort: [SortDescriptor(\WorkJob.date), SortDescriptor(\WorkJob.createdAt)]) private var allJobs: [WorkJob]
    @AppStorage("weeklySheetID") private var selectedID = ""
    @AppStorage("weeklyAlsoPDF") private var alsoPDF = true

    @State private var editing: JobTarget?
    @State private var importing = false
    @State private var editingDates = false
    @State private var needsSetup = false
    @State private var showSetup = false
    @State private var confirmReplace = false
    @State private var confirmDeleteWeek = false
    @State private var result: WeeklyResult?
    @State private var error: String?

    enum JobTarget: Identifiable {
        case new(Date?)
        case edit(WorkJob)
        var id: String {
            switch self {
            case .new(let d): "new-\(d?.timeIntervalSince1970 ?? 0)"
            case .edit(let j): "\(j.persistentModelID)"
            }
        }
    }

    private var store: WeeklyStore { WeeklyStore(context: context) }
    private var sheet: WeekSheet? { sheets.first { $0.sheetID == selectedID } ?? sheets.first }
    private var jobs: [WorkJob] { sheet.map { s in allJobs.filter { $0.sheetID == s.sheetID } } ?? [] }
    private var total: Decimal { jobs.compactMap(\.amount).reduce(0, +) }
    private var missing: Int { jobs.filter { !$0.hasAmount }.count }
    private var isSetUp: Bool { !business.contractorName.isEmpty && files.hasTemplate }
    private var filename: String { sheet.map { store.log(for: $0).filename } ?? "" }

    var body: some View {
        NavigationStack {
            List {
                if let sheet {
                    Section {
                        Text("Log each house you clean. At the end of the week, create the client's spreadsheet.")
                            .foregroundStyle(Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .plainRow(top: 0, bottom: 14)
                        weekPlate(sheet).plainRow(top: 6, bottom: 8, horizontal: 22)
                        VStack(spacing: 12) {
                            Button { editing = .new(nil) } label: { Label("Add a house", systemImage: "plus") }
                                .buttonStyle(PrimaryButtonStyle())
                            Button { importing = true } label: { Label("Paste from email", systemImage: "doc.on.clipboard") }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        .plainRow(top: 18, bottom: 8, horizontal: 22)
                    }

                    if jobs.isEmpty {
                        Section {
                            Text("No houses yet. Tap Add a house after each job, or paste the weekly email to fill the list in one go.")
                                .foregroundStyle(Color.inkSecondary)
                                .hairlineCell(first: true, verticalPadding: 14)
                        } header: { header("Houses") }
                    } else {
                        ForEach(groupedByDay, id: \.day) { group in
                            Section {
                                ForEach(Array(group.jobs.enumerated()), id: \.element.id) { i, job in
                                    jobRow(job, first: i == 0)
                                }
                            } header: {
                                HStack {
                                    SectionHeader(dayTitle(group.day))
                                    Spacer()
                                    Button { editing = .new(group.day) } label: {
                                        Image(systemName: "plus").font(.system(size: 15, weight: .medium))
                                    }
                                    .foregroundStyle(Color.accentInk)
                                    .accessibilityLabel("Add a house on \(dayTitle(group.day))")
                                    .padding(.trailing, 16)
                                }
                                .padding(.top, 14)
                            }
                        }

                        if !sheet.notes.isEmpty {
                            Section {
                                Text(sheet.notes).foregroundStyle(Color.inkSecondary)
                                    .hairlineCell(first: true, verticalPadding: 12)
                            } header: { header("Notes · not on the spreadsheet") }
                        }

                        Section {
                            Toggle("Also save a PDF", isOn: $alsoPDF)
                                .toggleStyle(SquareToggleStyle())
                                .hairlineCell(first: true)
                            VStack(spacing: 8) {
                                Button("Create spreadsheet", action: create)
                                    .buttonStyle(PrimaryButtonStyle())
                                Text(isSetUp ? "Fills the client's template: \(filename)"
                                     : "First time: you'll add your contractor info and the client's blank template.")
                                    .footnoteStyle()
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.bottom, 32)
                            .plainRow(top: 28, horizontal: 22)
                        } header: { header("When the week is done") }
                    }
                }
            }
            .industryList()
            .navigationTitle("Weekly")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { weeksMenu }
            }
            .navigationDestination(isPresented: $showSetup) {
                WeeklySetupView(business: business, suggestion: nil)
            }
        }
        .onAppear(perform: ensureSheet)
        .onChange(of: router.incomingEmail) { if router.incomingEmail != nil { importing = true } }
        .sheet(item: $editing) { target in
            if let sheet {
                NavigationStack { JobEditorView(sheet: sheet, target: target) }.tint(.accentInk)
            }
        }
        .sheet(isPresented: $importing) {
            if let sheet {
                NavigationStack {
                    ImportEmailView(sheet: sheet) { target in
                        selectedID = target.sheetID
                        importing = false
                    }
                }
                .tint(.accentInk)
            }
        }
        .sheet(isPresented: $editingDates) {
            if let sheet { NavigationStack { WeekDatesView(sheet: sheet) }.tint(.accentInk).presentationDetents([.large]) }
        }
        .sheet(isPresented: $needsSetup) {
            NavigationStack {
                WeeklySetupView(business: business, suggestion: nil) {
                    needsSetup = false
                    if isSetUp { create() }
                }
            }
            .tint(.accentInk)
        }
        .sheet(item: $result) { WeeklyResultView(result: $0) }
        .confirmationDialog("\(filename) already exists.", isPresented: $confirmReplace, titleVisibility: .visible) {
            Button("Replace") { write() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this week and its \(String(jobs.count)) houses?", isPresented: $confirmDeleteWeek,
                            titleVisibility: .visible) {
            Button("Delete week", role: .destructive) {
                if let sheet { store.delete(sheet); selectedID = ""; ensureSheet() }
            }
        }
        .alert("Couldn't create the spreadsheet", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    // MARK: pieces

    private func weekPlate(_ sheet: WeekSheet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sheet.sheetID == sheets.first?.sheetID ? "This week" : "Past week").kickerStyle()
            Button { editingDates = true } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(sheet.label).font(.condensed(26, relativeTo: .title2)).monospacedDigit()
                        .foregroundStyle(Color.ink)
                    Image(systemName: "calendar").font(.system(size: 15)).foregroundStyle(Color.accentInk)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Week of \(sheet.label)")
            .accessibilityHint("Change the dates")
            HStack(alignment: .firstTextBaseline) {
                Text("\(String(jobs.count)) house\(jobs.count == 1 ? "" : "s")")
                Spacer()
                Text(Money.format(total)).font(.condensed(26, relativeTo: .title2)).monospacedDigit()
            }
            .foregroundStyle(Color.ink)
            if missing > 0 {
                Text("\(String(missing)) without an amount — tap one to add it, or leave it blank.")
                    .font(.barlow(14, relativeTo: .subheadline)).foregroundStyle(Color.warning)
            }
            if let exported = sheet.exportedAt {
                Text("Spreadsheet created \(Dates.mdy(exported))")
                    .font(.barlow(14, relativeTo: .subheadline)).foregroundStyle(Color.accentInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .blueprint(bordered: true)
    }

    private func jobRow(_ job: WorkJob, first: Bool) -> some View {
        Button { editing = .edit(job) } label: {
            HStack(spacing: 12) {
                TwoLineLabel(title: job.client.isEmpty ? "(no client)" : job.client, subtitle: job.address)
                if let amount = job.amount {
                    Text(Money.format(amount)).monospacedDigit()
                } else {
                    Text("Add amount").font(.barlow(15, FontName.medium)).foregroundStyle(Color.accentInk)
                }
            }
        }
        .buttonStyle(RowButtonStyle(first: first, fill: job.hasAmount ? .clear : .accentTint))
        .listRowChrome()
        .swipeActions {
            Button("Delete", role: .destructive) { context.delete(job); try? context.save() }
        }
        .accessibilityLabel("\(job.client), \(job.address), \(job.amount.map(Money.format) ?? "no amount")")
        .accessibilityHint("Edit")
    }

    private var weeksMenu: some View {
        Menu {
            Button("Start a new week", systemImage: "plus") {
                selectedID = store.startNextWeek(after: sheets.first).sheetID
            }
            Button("Change this week's dates", systemImage: "calendar") { editingDates = true }
            if sheets.count > 1 {
                Section("Weeks") {
                    ForEach(sheets) { s in
                        Button { selectedID = s.sheetID } label: {
                            if s.sheetID == sheet?.sheetID { Label(s.label, systemImage: "checkmark") } else { Text(s.label) }
                        }
                    }
                }
            }
            Section {
                Button("Contractor info & template", systemImage: "doc.badge.gearshape") { showSetup = true }
                Button("Delete this week", systemImage: "trash", role: .destructive) { confirmDeleteWeek = true }
            }
        } label: {
            Image(systemName: "calendar")
        }
        .buttonStyle(SquareIconButtonStyle())
        .accessibilityLabel("Weeks and setup")
    }

    private struct DayGroup { let day: Date; let jobs: [WorkJob] }

    private var groupedByDay: [DayGroup] {
        var groups: [DayGroup] = []
        for job in jobs {
            let day = Dates.day(job.date)
            if let last = groups.last, last.day == day {
                groups[groups.count - 1] = DayGroup(day: day, jobs: last.jobs + [job])
            } else {
                groups.append(DayGroup(day: day, jobs: [job]))
            }
        }
        return groups
    }

    private func dayTitle(_ day: Date) -> String {
        let weekday = Dates.calendar.shortWeekdaySymbols[Dates.calendar.component(.weekday, from: day) - 1]
        let p = Dates.parts(day)
        return "\(weekday) \(String(format: "%02d/%02d", p.month, p.day))"
    }

    private func ensureSheet() {
        if sheet == nil { selectedID = store.currentSheet().sheetID }
        if router.incomingEmail != nil { importing = true }
        #if DEBUG
        if DebugLaunch.openScreen == "addHouse" { editing = .new(nil) }
        if DebugLaunch.openScreen == "editHouse", let job = jobs.last(where: { $0.hasAmount }) { editing = .edit(job) }
        #endif
    }

    // MARK: export

    private func create() {
        guard let sheet, !jobs.isEmpty else { return }
        if !isSetUp { needsSetup = true; return }
        if files.exists(store.log(for: sheet).filename) { confirmReplace = true; return }
        write()
    }

    private func write() {
        guard let sheet else { return }
        let log = store.log(for: sheet)
        do {
            let template = try Data(contentsOf: files.templateURL)
            let xlsx = try WeeklyInvoice.fill(template: template, contractor: business.contractor, log: log)
            try files.write(xlsx, named: log.filename)
            var out = [WeeklyResult.File(name: log.filename, data: xlsx, type: .xlsx)]
            var message = "Saved \(log.filename)"
            if alsoPDF {
                do {
                    let pdf = try WeeklyInvoice.pdf(xlsx: xlsx)
                    let name = WeeklyInvoice.pdfFilename(for: log.filename)
                    try files.write(pdf, named: name)
                    out.append(.init(name: name, data: pdf, type: .pdf))
                    message += " and .pdf"
                } catch {
                    message += " (couldn't create the PDF: \(error.localizedDescription))"
                }
            }
            sheet.exportedAt = Date()
            try? context.save()
            toast.show(message)
            result = WeeklyResult(files: out, location: files.locationName)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Change the first and last day of a week.
struct WeekDatesView: View {
    @Bindable var sheet: WeekSheet
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date()
    @State private var end = Date()

    var body: some View {
        List {
            Section {
                DatePicker("First day", selection: $start, displayedComponents: .date)
                    .hairlineCell(first: true)
                DatePicker("Last day", selection: $end, in: start..., displayedComponents: .date)
                    .hairlineCell()
                Footnote("These are the Period Start and End dates on the client's spreadsheet.")
            } header: { header("Work week") }
        }
        .industryList()
        .navigationTitle("Week dates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    sheet.start = Dates.day(start)
                    sheet.end = Dates.day(max(start, end))
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear { start = sheet.start; end = sheet.end }
    }
}
