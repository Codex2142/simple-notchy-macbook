// swift-tools-version: 5.9
import PackageDescription
import Foundation

let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let rustLibDir = URL(fileURLWithPath: packageDir)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("target/debug")
    .path

let package = Package(
    name: "ProjectIslandMacOS",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "IslandBridge", targets: ["IslandBridge"]),
        .library(name: "IslandWindow", targets: ["IslandWindow"]),
        .library(name: "IslandIntegrations", targets: ["IslandIntegrations"]),
        .library(name: "IslandFeatures", targets: ["IslandFeatures"]),
        .executable(name: "ProjectIslandApp", targets: ["ProjectIslandApp"]),
        .executable(name: "IslandSelfTest", targets: ["IslandSelfTest"]),
    ],
    targets: [
        .target(
            name: "CIslandBridge",
            path: "Sources/CIslandBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .unsafeFlags(["-L\(rustLibDir)", "-lisland_bridge"])
            ]
        ),
        .target(
            name: "IslandBridge",
            dependencies: ["CIslandBridge"],
            path: "Sources/Bridge"
        ),
        .target(
            name: "IslandWindow",
            dependencies: ["IslandBridge"],
            path: "Sources/Window"
        ),
        .target(
            name: "IslandIntegrations",
            dependencies: ["IslandBridge"],
            path: "Sources/Integrations"
        ),
        .target(
            name: "IslandFeatures",
            dependencies: ["IslandBridge", "IslandWindow", "IslandIntegrations"],
            path: "Sources/Features"
        ),
        .executableTarget(
            name: "ProjectIslandApp",
            dependencies: ["IslandWindow", "IslandBridge", "IslandIntegrations", "IslandFeatures"],
            path: "Sources/App"
        ),
        .executableTarget(
            name: "IslandSelfTest",
            dependencies: ["IslandWindow", "IslandBridge", "IslandIntegrations", "IslandFeatures"],
            path: "Sources/SelfTest"
        ),
        .testTarget(
            name: "WindowTests",
            dependencies: ["IslandWindow", "IslandBridge", "IslandIntegrations", "IslandFeatures"],
            path: "Tests/WindowTests"
        ),
    ]
)
