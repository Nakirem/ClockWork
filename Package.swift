// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClockWorkCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "ClockWorkCore", targets: ["ClockWorkCore"])],
    targets: [
        .target(name: "ClockWorkCore", path: "ClockWork/Domain"),
        .testTarget(name: "ClockWorkCoreTests", dependencies: ["ClockWorkCore"], path: "Tests/Core")
    ]
)
