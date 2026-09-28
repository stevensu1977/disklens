// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiskLens",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DiskLens", targets: ["DiskLens"]),
        .library(name: "StorageCore", targets: ["StorageCore"])
    ],
    targets: [
        .target(name: "StorageTraversal", publicHeadersPath: "include"),
        .target(name: "StorageCore", dependencies: ["StorageTraversal"]),
        .executableTarget(name: "DiskLens", dependencies: ["StorageCore"], path: "Sources/StorageMaster"),
        .testTarget(name: "StorageCoreTests", dependencies: ["StorageCore"])
    ]
)
