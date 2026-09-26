// swift-tools-version: 5.9
import PackageDescription

// Two executables named "stale" and "Stale" would collide in .build on a
// case-insensitive volume, so the app target is StaleApp; build.sh renames the
// binary to Stale inside Stale.app.
let package = Package(
    name: "Stale",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "stale", targets: ["stale"]),
        .executable(name: "StaleApp", targets: ["StaleApp"]),
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
        .executableTarget(
            name: "StaleApp",
            dependencies: ["StaleCore"],
            path: "Sources/StaleApp"
        ),
        .testTarget(
            name: "StaleCoreTests",
            dependencies: ["StaleCore"],
            path: "Tests/StaleCoreTests"
        ),
    ]
)
