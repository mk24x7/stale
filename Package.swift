// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Stale",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "stale", targets: ["stale"]),
        .library(name: "StaleCore", targets: ["StaleCore"]),
    ],
    targets: [
        .target(
            name: "StaleCore",
            path: "Sources/StaleCore"
        ),
        .executableTarget(
            name: "stale",
            dependencies: ["StaleCore"],
            path: "Sources/stale"
        ),
        .testTarget(
            name: "StaleCoreTests",
            dependencies: ["StaleCore"],
            path: "Tests/StaleCoreTests"
        ),
    ]
)
