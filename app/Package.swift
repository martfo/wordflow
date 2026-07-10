// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WordFlow",
    platforms: [.macOS("14.4")],
    targets: [
        .target(
            name: "WordFlowCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "WordFlowApp",
            dependencies: ["WordFlowCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "WordFlowCoreTests",
            dependencies: ["WordFlowCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
