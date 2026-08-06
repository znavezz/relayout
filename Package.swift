// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "relayout",
    platforms: [
        .macOS(.v10_15)
    ],
    targets: [
        .executableTarget(
            name: "relayout",
            path: "Sources/relayout"
        )
    ]
)
