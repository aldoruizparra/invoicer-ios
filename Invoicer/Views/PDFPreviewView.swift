import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Full-screen PDF after Confirm and from history: Share (Mail, Messages,
/// AirDrop…) and Save to Files.
struct PDFPreviewView: View {
    let item: PreviewItem
    @Environment(\.dismiss) private var dismiss
    @Environment(FileStore.self) private var files
    @Environment(Toast.self) private var toast
    @State private var exporting = false
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            PDFKitView(data: item.data)
                .ignoresSafeArea(edges: .bottom)
                .background(Color.toggleOff.opacity(0.6))
                .accessibilityLabel("Invoice PDF, \(item.filename)")
                .navigationTitle(item.filename)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }.fontWeight(.semibold)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    HStack(spacing: 12) {
                        if let shareURL {
                            ShareLink(item: shareURL, subject: Text(item.filename),
                                      preview: SharePreview(item.filename, icon: Image(systemName: "doc.richtext"))) {
                                Text("Share")
                            }
                            .buttonStyle(PrimaryButtonStyle(height: 46, marks: false))
                        }
                        Button("Save to Files") { exporting = true }
                            .buttonStyle(SecondaryButtonStyle(height: 46))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                    .background(.thinMaterial)
                    .overlay(alignment: .top) { Rectangle().fill(Color.divider).frame(height: 1) }
                }
        }
        .tint(.accentInk)
        .toastOverlay(toast)
        .onAppear { shareURL = files.temporaryCopy(item.data, named: item.filename) ?? item.url }
        .fileExporter(isPresented: $exporting, document: ExportFile(data: item.data, type: .pdf),
                      contentType: .pdf, defaultFilename: item.filename) { result in
            if case .success = result { toast.show("Saved \(item.filename) to Files") }
        }
    }
}

/// PDFView showing the document; the page gets the blueprint registration marks.
struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.pageShadowsEnabled = true
        view.backgroundColor = .clear
        view.pageOverlayViewProvider = context.coordinator
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.dataRepresentation() != data { view.document = PDFDocument(data: data) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, PDFPageOverlayViewProvider {
        nonisolated func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
            // PDFKit asks on the main thread.
            MainActor.assumeIsolated {
                let overlay = MarksOverlay()
                overlay.isUserInteractionEnabled = false
                return overlay
            }
        }
    }

    /// Four "+" marks just outside the page corners.
    final class MarksOverlay: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = false
            backgroundColor = .clear
            isAccessibilityElement = false
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            layer.sublayers?.forEach { $0.removeFromSuperlayer() }
            let mark = CAShapeLayer()
            let path = UIBezierPath()
            let w = bounds.width, h = bounds.height
            for (x, y) in [(-6.5, -6.5), (w + 6.5, -6.5), (-6.5, h + 6.5), (w + 6.5, h + 6.5)] {
                path.move(to: CGPoint(x: x - 5.5, y: y)); path.addLine(to: CGPoint(x: x + 5.5, y: y))
                path.move(to: CGPoint(x: x, y: y - 5.5)); path.addLine(to: CGPoint(x: x, y: y + 5.5))
            }
            mark.path = path.cgPath
            mark.lineWidth = 1
            mark.strokeColor = UIColor(named: "Ink")!.withAlphaComponent(0.55).cgColor
            layer.addSublayer(mark)
        }
    }
}

/// Bytes handed to `fileExporter`.
struct ExportFile: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf, .xlsx]
    let data: Data
    let type: UTType

    init(data: Data, type: UTType) { self.data = data; self.type = type }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        type = configuration.contentType
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

extension UTType {
    static let xlsx = UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data
    static let eml = UTType(filenameExtension: "eml") ?? UTType("com.apple.mail.email") ?? .emailMessage
}
