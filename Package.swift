// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexUsageMenuBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexUsageMenuBar", targets: ["CodexUsageMenuBar"])
    ],
    targets: [
        .executableTarget(name: "CodexUsageMenuBar")
    ],
    swiftLanguageVersions: [.v5]
)
