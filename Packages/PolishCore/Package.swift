// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PolishCore",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "PolishCore", targets: ["PolishCore"]),
        .executable(name: "polish-cli", targets: ["PolishCLI"]),
    ],
    targets: [
        .target(name: "PolishCore"),
        // Golden-set harness and quick rewrites from the terminal; see `polish-cli help`.
        .executableTarget(name: "PolishCLI", dependencies: ["PolishCore"]),
        .testTarget(name: "PolishCoreTests", dependencies: ["PolishCore"]),
    ]
)
