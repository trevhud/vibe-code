// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VibeCodeCLI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "vibe-code",
            targets: ["VibeCodeCLI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "2.0.0"),
        .package(url: "https://github.com/fwcd/swift-qrcode-generator.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "VibeCodeCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "QRCodeGenerator", package: "swift-qrcode-generator")
            ],
            path: "Sources/VibeCodeCLI",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "VibeCodeCLITests",
            dependencies: ["VibeCodeCLI"],
            path: "Tests/VibeCodeCLITests"
        )
    ]
)