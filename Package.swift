// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TokenGauge",
    defaultLocalization: "es",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TokenGaugeCore", targets: ["TokenGaugeCore"]),
        .executable(name: "TokenGaugeApp", targets: ["TokenGaugeApp"]),
        .executable(name: "TokenGaugeCapture", targets: ["TokenGaugeCapture"]),
    ],
    targets: [
        .target(name: "TokenGaugeCore"),
        .executableTarget(
            name: "TokenGaugeApp",
            dependencies: ["TokenGaugeCore"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "TokenGaugeCapture",
            dependencies: ["TokenGaugeCore"]
        ),
        .testTarget(
            name: "TokenGaugeCoreTests",
            dependencies: ["TokenGaugeCore"]
        ),
        .testTarget(
            name: "TokenGaugeAppTests",
            dependencies: ["TokenGaugeApp", "TokenGaugeCore"]
        ),
    ]
)
