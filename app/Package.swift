// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WatchLogs",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "WatchLogsKit"
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
