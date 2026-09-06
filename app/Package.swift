// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WatchLogs",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // A debug tool, built from the same module the app runs on so it can
        // never drift from it. Not shipped.
        .executable(name: "wl-replay", targets: ["WLReplay"])
    ],
    targets: [
        .target(
            name: "WatchLogsKit"
        ),
        .executableTarget(
            name: "WLReplay",
            dependencies: ["WatchLogsKit"]
        ),
        .executableTarget(
            name: "WatchLogs",
            dependencies: ["WatchLogsKit"]
        ),
        .testTarget(
            name: "WatchLogsKitTests",
            dependencies: ["WatchLogsKit"]
        ),
    ]
)
