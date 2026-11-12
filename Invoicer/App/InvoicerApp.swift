import InvoicerKit
import SwiftData
import SwiftUI

@main
struct InvoicerApp: App {
    @AppStorage("iCloudSync") private var syncEnabled = true
    @State private var files: FileStore
    @State private var toast = Toast()
    @State private var router = Router()

    init() {
        Appearance.apply()
        let sync = UserDefaults.standard.object(forKey: "iCloudSync") as? Bool ?? true
        _files = State(initialValue: FileStore(syncEnabled: sync))
    }

    var body: some Scene {
        WindowGroup {
            ContainerHost(syncEnabled: syncEnabled)
                .environment(files)
                .environment(toast)
                .environment(router)
                .tint(.accentInk)
                .font(.barlow())
                .toastOverlay(toast)
                .task { await files.resolveICloud() }
                .onChange(of: syncEnabled) { _, on in files.syncEnabled = on }
                .onOpenURL { url in router.open(url) }
        }
    }
}

/// Builds the SwiftData container for the current sync setting. Toggling iCloud
/// sync rebuilds it on the same store file, so local data is kept either way.
struct ContainerHost: View {
    let syncEnabled: Bool
    @State private var holder: ContainerHolder?

    var body: some View {
        Group {
            if let holder, holder.syncEnabled == syncEnabled {
                RootView(cloudAvailable: holder.cloudKitActive)
                    .modelContainer(holder.container)
            } else {
                Color.ground.ignoresSafeArea()
            }
        }
        .task(id: syncEnabled) { holder = ContainerHolder.make(sync: syncEnabled) }
    }
}

struct ContainerHolder {
    let container: ModelContainer
    let syncEnabled: Bool
    let cloudKitActive: Bool

    static var storeURL: URL { URL.applicationSupportDirectory.appendingPathComponent("Invoicer.store") }

    @MainActor
    static func make(sync: Bool) -> ContainerHolder {
        #if DEBUG
        if let demo = DebugLaunch.demoContainer() {
            return ContainerHolder(container: demo, syncEnabled: sync, cloudKitActive: false)
        }
        #endif
        let schema = Schema(Schema1.models)
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        if sync {
            let config = ModelConfiguration("Invoicer", schema: schema, url: storeURL,
                                            cloudKitDatabase: .private(FileStore.containerID))
            if let container = try? ModelContainer(for: schema, configurations: config) {
                return ContainerHolder(container: container, syncEnabled: sync, cloudKitActive: true)
            }
        }
        // Local only (sync off, or iCloud/CloudKit isn't available on this device).
        let local = ModelConfiguration("Invoicer", schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = (try? ModelContainer(for: schema, configurations: local))
            ?? (try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        return ContainerHolder(container: container, syncEnabled: sync, cloudKitActive: false)
    }
}

/// App-wide navigation: selected tab, the invoice sheet, the PDF preview and
/// files opened from other apps.
@MainActor
@Observable
final class Router {
    enum Tab: Hashable { case invoices, weekly, saved, settings }

    var tab: Tab = .invoices
    var invoiceSheet: InvoiceDraft?
    var preview: PreviewItem?
    /// An .eml handed to the app (Share Sheet / Open In), waiting for the Weekly tab.
    var incomingEmail: URL?

    func open(_ url: URL) {
        guard url.pathExtension.lowercased() == "eml" || url.isFileURL else { return }
        invoiceSheet = nil
        preview = nil
        incomingEmail = url
        tab = .weekly
    }
}

/// What the full-screen PDF preview shows.
struct PreviewItem: Identifiable {
    let id = UUID()
    let filename: String
    let data: Data
    let url: URL?
}
