// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PolishCore",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "PolishCore", targets: ["PolishCore"]),
    ],
    targets: [
        .target(name: "PolishCore"),
        .testTarget(name: "PolishCoreTests", dependencies: ["PolishCore"]),
    ]
)
