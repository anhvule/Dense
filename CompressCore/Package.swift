// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CompressCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "CompressCore", targets: ["CompressCore"])],
    targets: [
        .target(name: "CompressCore"),
        .testTarget(name: "CompressCoreTests", dependencies: ["CompressCore"]),
    ]
)
