// swift-tools-version: 6.2

import PackageDescription

/// Runs on every build, so a violation shows up where the code is written
/// rather than at commit time.
let lint: Target.PluginUsage = .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")

let package = Package(
    name: "ASCKitEngine",
    // Every user-facing sentence is a LocalizedStringResource, and that type
    // only became Sendable in macOS 15.
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ASCKitAPI", targets: ["ASCKitAPI"]),
        .library(name: "ASCKitProject", targets: ["ASCKitProject"]),
        .library(name: "ASCKitTestSupport", targets: ["ASCKitTestSupport"]),
        .executable(name: "asckit", targets: ["asckit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        // Prebuilt binaries, so linting does not mean compiling SwiftLint.
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.65.0")
    ],
    targets: [
        // Talks to Apple. No file system, no configuration.
        .target(
            name: "ASCKitAPI",
            resources: [.process("Resources")],
            plugins: [lint]
        ),

        // Reads configuration and content. Never opens a socket.
        .target(
            name: "ASCKitProject",
            dependencies: ["ASCKitAPI"],
            resources: [.process("Resources")],
            plugins: [lint]
        ),

        // Stubs shared by every test target, the app's own included, so there
        // is one fake App Store Connect rather than one per test bundle.
        //
        // A product because the app's test bundle is an Xcode target and can
        // only reach it that way. Nothing that ships may link it: it answers
        // canned replies and carries a throwaway key.
        .target(
            name: "ASCKitTestSupport",
            dependencies: ["ASCKitAPI"],
            plugins: [lint]
        ),

        .executableTarget(
            name: "asckit",
            dependencies: [
                "ASCKitAPI",
                "ASCKitProject",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            plugins: [lint]
        ),

        .testTarget(
            name: "ASCKitAPITests",
            dependencies: ["ASCKitAPI", "ASCKitTestSupport"],
            plugins: [lint]
        ),
        .testTarget(
            name: "ASCKitProjectTests",
            dependencies: ["ASCKitProject", "ASCKitTestSupport"],
            plugins: [lint]
        )
    ]
)
