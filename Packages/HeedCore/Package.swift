// swift-tools-version: 5.9
import PackageDescription

// Pure logic shared by the app and the widget: day keys, recurrence, quick-add parsing, reminder planning, filters,
// backups. No UI and no SwiftData here, so `swift test` runs it on the Mac in seconds.
let package = Package(
    name: "HeedCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "HeedCore", targets: ["HeedCore"])],
    targets: [
        .target(name: "HeedCore"),
        .testTarget(name: "HeedCoreTests", dependencies: ["HeedCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
