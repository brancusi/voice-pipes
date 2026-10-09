// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceTools",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.4"),
        // Keep in step with SPARKLE_VERSION in build.sh (its bin/sign_update signs releases).
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
        // TOML 1.1 decoding for config.toml (MIT, pure Swift). The app writes the file itself.
        .package(url: "https://github.com/dduan/TOMLDecoder", exact: "0.4.5"),
    ],
    targets: [
        .executableTarget(
            name: "VoiceTools",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "TOMLDecoder", package: "TOMLDecoder"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        // Catches the NSExceptions AVFoundation raises on audio-device changes (Swift can't).
    ]
)
