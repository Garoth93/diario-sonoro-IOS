// swift-tools-version: 5.9
// Logic package for the Diario Sonoro app. Pure Swift (Foundation only):
// it must build and test on Linux with `swift test`.
import PackageDescription

let package = Package(
    name: "SonoroCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "SonoroCore", targets: ["SonoroCore"])
    ],
    targets: [
        .target(
            name: "SonoroCore",
            path: "Sources/SonoroCore"
        ),
        .testTarget(
            name: "SonoroCoreTests",
            dependencies: ["SonoroCore"],
            path: "Tests/SonoroCoreTests"
        )
    ]
)
