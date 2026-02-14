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
    dependencies: [],
    targets: [
        .executableTarget(
            name: "NexusApp",
            dependencies: [],
            path: "Sources/NexusApp",
            exclude: [
                "README.md", "Core/README.md", "Core/Network/README.md", "Core/Storage/README.md",
                "Domain/README.md", "Domain/Models/README.md", "Domain/Protocols/README.md",
                "Presentation/README.md", "Utilities/README.md",
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "NexusHost",
            dependencies: [],
            path: "Sources/NexusHost",
            exclude: ["README.md"]
        ),
    ]
)
