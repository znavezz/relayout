// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "cmd-m",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "cmd-m",
            path: "Sources/cmd-m"
        )
    ]
)
