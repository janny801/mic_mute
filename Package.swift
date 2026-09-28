// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacMicMute",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MacMicMute",
            targets: ["MacMicMute"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MacMicMute",
            dependencies: [],
            path: "Sources/MacMicMute"
        )
    ]
)
