// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Stale",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "StaleCore", targets: ["StaleCore"]),
    ],
    targets: [
        .target(
            name: "StaleCore",
            path: "Sources/StaleCore"
        ),
    ]
)
