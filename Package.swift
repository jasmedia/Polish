// swift-tools-version: 6.0
// The Polish menu bar app. Build and run with `make run` (see scripts/bundle.sh).
// The rewrite engine lives in the local PolishCore package.
import PackageDescription

let package = Package(
    name: "Polish",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "Polish", targets: ["Polish"]),
    ],
    dependencies: [
        .package(path: "Packages/PolishCore"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "Polish",
            dependencies: [
                .product(name: "PolishCore", package: "PolishCore"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "App/Sources"
        ),
        .testTarget(
            name: "PolishTests",
            dependencies: ["Polish"],
            path: "App/Tests"
        ),
    ]
)
