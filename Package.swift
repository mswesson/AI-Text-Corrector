// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "TextCorrect",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TextCorrectCore", targets: ["TextCorrectCore"]),
        .library(name: "TextCorrectSpeech", targets: ["TextCorrectSpeech"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7", traits: []),
    ],
    targets: [
        .binaryTarget(
            name: "WhisperFramework",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/v1.7.5/whisper-v1.7.5-xcframework.zip",
            checksum: "c7faeb328620d6012e130f3d705c51a6ea6c995605f2df50f6e1ad68c59c6c4a"
        ),
        .target(
            name: "TextCorrectSpeech",
            dependencies: ["TextCorrectCore", "WhisperFramework", .product(name: "FluidAudio", package: "FluidAudio")]
        ),
        .target(
            name: "TextCorrectCore",
            path: "Sources/TextCorrectCore",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "TextCorrect",
            dependencies: ["TextCorrectCore", "TextCorrectSpeech"],
            path: "Sources/TextCorrect",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
            ]
        ),
        .executableTarget(
            name: "SpeechCheck",
            dependencies: ["TextCorrectCore", "TextCorrectSpeech"],
            path: "Tools/SpeechCheck"
        ),
        .testTarget(
            name: "TextCorrectSpeechTests",
            dependencies: ["TextCorrectSpeech", "TextCorrectCore"]
        ),
        .testTarget(
            name: "TextCorrectCoreTests",
            dependencies: ["TextCorrectCore"],
            path: "Tests/TextCorrectCoreTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
