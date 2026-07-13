// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DenseCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "DenseCore", targets: ["DenseCore"])],
    targets: [
        .target(name: "DenseCore"),
        .testTarget(name: "DenseCoreTests", dependencies: ["DenseCore"]),
    ]
)
