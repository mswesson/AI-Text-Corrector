// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TextCorrect",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "TextCorrectCore",
            path: "Sources/TextCorrectCore",
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "TextCorrect",
            dependencies: ["TextCorrectCore"],
            path: "Sources/TextCorrect",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AVFoundation"),
            ]
        ),
        .testTarget(
            name: "TextCorrectCoreTests",
            dependencies: ["TextCorrectCore"],
            path: "Tests/TextCorrectCoreTests"
        ),
    ]
)
