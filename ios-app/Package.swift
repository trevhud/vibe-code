// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VibeCode",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "VibeCode",
            targets: ["VibeCode"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.3.0")
    ],
    targets: [
        .target(
            name: "VibeCode",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh")
            ]
        ),
        .testTarget(
            name: "VibeCodeTests",
            dependencies: ["VibeCode"]
        )
    ]
)