// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Nexus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Nexus",
            targets: ["NexusApp"]),
        .executable(
            name: "NexusHost",
            targets: ["NexusHost"]),
    ],
    dependencies: [
    ],
    targets: [
        .executableTarget(
            name: "NexusApp",
            dependencies: [],
            path: "Sources/NexusApp",
            resources: [
                .process("Resources") 
            ]
        ),
        .executableTarget(
            name: "NexusHost",
            dependencies: [],
            path: "Sources/NexusHost"
        ),
        .testTarget(
            name: "NexusTests",
            dependencies: ["NexusApp"]),
    ]
)
