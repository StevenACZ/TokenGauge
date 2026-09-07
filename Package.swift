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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        .target(name: "TokenGaugeCore"),
        .executableTarget(
            name: "TokenGaugeApp",
            dependencies: ["TokenGaugeCore", .product(name: "Sparkle", package: "Sparkle")],
            resources: [.process("Resources")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
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
