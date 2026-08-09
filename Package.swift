// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PlaneFuse",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PlaneFuseCore", targets: ["PlaneFuseCore"]),
        .executable(name: "planefuse", targets: ["PlaneFuseCLI"]),
    ],
    targets: [
        .target(name: "PlaneFuseCore"),
        .executableTarget(name: "PlaneFuseCLI", dependencies: ["PlaneFuseCore"]),
        .testTarget(name: "PlaneFuseCoreTests", dependencies: ["PlaneFuseCore"]),
    ]
)
