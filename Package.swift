// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Voicer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Voicer",
            path: "Sources/Voicer",
            resources: [.process("../../Resources")]
        )
    ]
)
