import InvoicerKit
import SwiftData
import SwiftUI

/// First launch shows Setup (= `invoice.py setup`); afterwards the tab bar.
struct RootView: View {
    let cloudAvailable: Bool
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Query(sort: \Business.createdAt) private var businesses: [Business]

    private var business: Business? { businesses.first(where: \.isSetUp) ?? businesses.first }

    var body: some View {
        @Bindable var router = router
        Group {
            if let business {
                if business.isSetUp {
                    MainTabs(business: business, cloudAvailable: cloudAvailable)
                } else {
                    SetupView(business: business)
                }
            } else {
                Color.ground.ignoresSafeArea()
                    .onAppear { _ = Store(context: context).business() }
            }
        }
        .fullScreenCover(item: $router.preview) { item in
            PDFPreviewView(item: item)
        }
    }
}

struct MainTabs: View {
    let business: Business
    let cloudAvailable: Bool
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            InvoicesView(business: business)
                .tabItem { Text("INVOICES") }
                .tag(Router.Tab.invoices)
                .accessibilityLabel("Invoices")
            WeeklyHomeView(business: business)
                .tabItem { Text("WEEKLY") }
                .tag(Router.Tab.weekly)
                .accessibilityLabel("Weekly")
            SavedView()
                .tabItem { Text("SAVED") }
                .tag(Router.Tab.saved)
                .accessibilityLabel("Saved")
            SettingsView(business: business, cloudAvailable: cloudAvailable)
                .tabItem { Text("SETTINGS") }
                .tag(Router.Tab.settings)
                .accessibilityLabel("Settings")
        }
        .sheet(item: $router.invoiceSheet) { draft in
            InvoiceSheet(draft: draft, business: business)
                .interactiveDismissDisabled(draft.hasContent)
        }
        #if DEBUG
        .task { openDebugScreen() }
        #endif
    }

    #if DEBUG
    @Environment(\.modelContext) private var context
    @Environment(FileStore.self) private var files

    /// `-openScreen <name>` for screenshots (see DebugLaunch).
    private func openDebugScreen() {
        guard let screen = DebugLaunch.openScreen else { return }
        let store = Store(context: context)
        switch screen {
        case "newInvoice", "contacts", "addresses", "item", "newContact": router.invoiceSheet = InvoiceDraft(business: business)
        case "repeat", "review":
            if let last = store.lastInvoice() { router.invoiceSheet = InvoiceDraft(repeating: last.data, business: business) }
        case "saved": router.tab = .saved
        case "settings": router.tab = .settings
        case "weekly", "addHouse", "editHouse": router.tab = .weekly
        case "paste":
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Invoice.eml")
            try? Data(DebugLaunch.sampleEmail.utf8).write(to: url)
            router.open(url)
        case "preview":
            if let last = store.lastInvoice() {
                let pdf = files.pdf(for: last.data, sender: business.sender)
                router.preview = PreviewItem(filename: last.data.filename, data: pdf.data, url: pdf.url)
            }
        case "demo": router.preview = PreviewItem(filename: "demo_invoice.pdf", data: Demo.pdf(), url: nil)
        default: break
        }
    }
    #endif
}
