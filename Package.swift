// swift-tools-version: 6.0
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
    swiftLanguageModes: [.v5]
)
