// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeAccounts",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "ClaudeAccounts",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/ClaudeAccounts",
            // scripts/build-app.sh assembles the .app by hand and puts Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ]
)
