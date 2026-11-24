// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NotifyBridge",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "NotifyBridge", path: "Sources/NotifyBridge", swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
