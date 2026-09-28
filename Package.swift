// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MicMute",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MicMute",
            targets: ["MicMute"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MicMute",
            dependencies: [],
            path: "Sources/MicMute"
        )
    ]
)
