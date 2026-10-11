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
        .executable(
            name: "ytd-e2e",
            targets: ["ytd-e2e"]),
    ],
    targets: [
        .target(
            name: "YTDownloaderCore",
            dependencies: [],
            path: "Sources/YTDownloaderCore"),
        .executableTarget(
            name: "ytd-e2e",
            dependencies: ["YTDownloaderCore"],
            path: "Sources/ytd-e2e"),
        .testTarget(
            name: "YTDownloaderCoreTests",
            dependencies: ["YTDownloaderCore"],
            path: "Tests/YTDownloaderCoreTests",
            resources: [.copy("Fixtures")]),
    ]
)
