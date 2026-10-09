// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeAccounts",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "ClaudeAccounts", path: "Sources/ClaudeAccounts"),
    ]
)
