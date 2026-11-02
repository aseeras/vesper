// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VesperCore",
    platforms: [.iOS("17.2"), .macOS(.v14)],
    products: [
        .library(name: "VesperCore", targets: ["VesperCore"]),
    ],
    targets: [
        .target(name: "VesperCore"),
        .testTarget(name: "VesperCoreTests", dependencies: ["VesperCore"]),
    ]
)
