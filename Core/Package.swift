// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WellkeptCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WellkeptCore", targets: ["WellkeptCore"]),
    ],
    targets: [
        .target(name: "WellkeptCore"),
        .testTarget(name: "WellkeptCoreTests", dependencies: ["WellkeptCore"]),
    ]
)
