// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tripad",
    platforms: [.macOS("14.0")],
    targets: [
        .executableTarget(
            name: "Tripad",
            path: "Sources/Tripad"
        )
    ]
)
