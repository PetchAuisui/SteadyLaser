// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SteadyLaser",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SteadyLaser",
            path: "Sources/SteadyLaser"
        ),
        .testTarget(
            name: "SteadyLaserTests",
            dependencies: ["SteadyLaser"],
            path: "Tests/SteadyLaserTests"
        ),
    ]
)
