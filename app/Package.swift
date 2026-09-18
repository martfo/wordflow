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
        // Objective-C so it can @try/@catch the NSExceptions AVAudioEngine
        // raises; Swift cannot, and an uncaught one aborts the app.
        .target(name: "WordFlowObjCSupport"),
        .executableTarget(
            name: "WordFlowApp",
            dependencies: ["WordFlowCore", "WordFlowObjCSupport"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "WordFlowCoreTests",
            dependencies: ["WordFlowCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
