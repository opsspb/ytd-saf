// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YTDownloaderCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "YTDownloaderCore",
            targets: ["YTDownloaderCore"]),
    ],
    targets: [
        .target(
            name: "YTDownloaderCore",
            dependencies: [],
            path: "Sources/YTDownloaderCore"),
        .testTarget(
            name: "YTDownloaderCoreTests",
            dependencies: ["YTDownloaderCore"],
            path: "Tests/YTDownloaderCoreTests",
            resources: [.copy("Fixtures")]),
    ]
)
