// swift-tools-version: 6.0
import PackageDescription

// Platform-neutral core of Invoicer: money, parsing, PDF and xlsx output.
// Only Apple system frameworks (Foundation, CoreGraphics, CoreText, ImageIO,
// Compression), so `swift test` runs on the Mac without a simulator.
let package = Package(
    name: "InvoicerKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "InvoicerKit", targets: ["InvoicerKit"]),
    ],
    targets: [
        .target(name: "InvoicerKit"),
        .testTarget(name: "InvoicerKitTests", dependencies: ["InvoicerKit"],
                    resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
