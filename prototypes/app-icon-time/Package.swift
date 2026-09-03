// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppIconTime",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "AppIconTime"
        )
    ]
)
