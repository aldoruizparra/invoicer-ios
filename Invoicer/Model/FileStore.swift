import Foundation
import InvoicerKit
import Observation

/// Where PDFs and spreadsheets go: iCloud Drive › Invoicer when sync is on and
/// iCloud is available, otherwise Files › On My iPhone › Invoicer › Invoices.
/// The weekly template lives privately in Application Support.
@MainActor
@Observable
final class FileStore {
    static let containerID = "iCloud.com.aldoruizparra.Invoicer"

    var syncEnabled: Bool
    /// The ubiquity container's Documents folder, once resolved (nil = unavailable).
    private(set) var iCloudDocuments: URL?
    private(set) var resolvedICloud = false
    private let localRoot: URL

    init(syncEnabled: Bool, localRoot: URL = URL.documentsDirectory) {
        self.syncEnabled = syncEnabled
        self.localRoot = localRoot
    }

    /// Look up the iCloud container off the main thread (it can block).
    func resolveICloud() async {
        let id = FileStore.containerID
        let url = await Task.detached { () -> URL? in
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: id) else { return nil }
            let docs = container.appendingPathComponent("Documents", isDirectory: true)
            try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            return docs
        }.value
        iCloudDocuments = url
        resolvedICloud = true
    }

    var usingICloud: Bool { syncEnabled && iCloudDocuments != nil }

    var outputDirectory: URL {
        if syncEnabled, let iCloudDocuments { return iCloudDocuments }
        return localRoot.appendingPathComponent("Invoices", isDirectory: true)
    }

    /// Human description of where files are saved, for toasts and footnotes.
    var locationName: String { usingICloud ? "iCloud Drive › Invoicer" : "Files › On My iPhone › Invoicer" }

    @discardableResult
    func write(_ data: Data, named name: String) throws -> URL {
        let dir = outputDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent(name).path)
    }

    /// The saved file, checking both locations (sync may have been toggled since).
    func existingURL(_ name: String) -> URL? {
        let candidates = [iCloudDocuments, localRoot.appendingPathComponent("Invoices", isDirectory: true)]
            .compactMap { $0?.appendingPathComponent(name) }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The invoice's PDF: the saved file if present, otherwise rendered again and saved.
    func pdf(for invoice: InvoiceData, sender: Sender) -> (data: Data, url: URL?) {
        if let url = existingURL(invoice.filename), let data = try? Data(contentsOf: url) {
            return (data, url)
        }
        let data = InvoicePDF.render(sender: sender, invoice: invoice)
        return (data, try? write(data, named: invoice.filename))
    }

    // MARK: weekly template (private, not synced)

    var templateURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("weekly_template.xlsx")
    }

    var hasTemplate: Bool { FileManager.default.fileExists(atPath: templateURL.path) }

    func saveTemplate(_ data: Data) throws {
        try WeeklyInvoice.validateTemplate(data)
        try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try data.write(to: templateURL, options: .atomic)
    }

    /// A temporary copy for sharing (keeps the share sheet off iCloud placeholders).
    func temporaryCopy(_ data: Data, named name: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("share", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        return (try? data.write(to: url, options: .atomic)) == nil ? nil : url
    }
}

/// Read a file the user picked (security-scoped URL from fileImporter / Open In).
func readPickedFile(_ url: URL) throws -> Data {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    return try Data(contentsOf: url)
}
