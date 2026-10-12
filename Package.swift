// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FreeScoreForMac",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "FreeScore", targets: ["FreeScore"])],
    targets: [
        .executableTarget(name: "FreeScore"),
        .testTarget(name: "FreeScoreTests", dependencies: ["FreeScore"])
    ]
)
