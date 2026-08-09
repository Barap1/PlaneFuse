// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PlaneFuse",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PlaneFuseCore", targets: ["PlaneFuseCore"]),
        .executable(name: "planefuse", targets: ["PlaneFuseCLI"]),
        .executable(name: "planefuse-live", targets: ["PlaneFuseLive"]),
    ],
    targets: [
        .target(
            name: "PlaneFuseCore",
            resources: [.process("Shaders")]
        ),
        .executableTarget(name: "PlaneFuseCLI", dependencies: ["PlaneFuseCore"]),
        .executableTarget(name: "PlaneFuseLive", dependencies: ["PlaneFuseCore"]),
        .testTarget(name: "PlaneFuseCoreTests", dependencies: ["PlaneFuseCore"]),
    ]
)
