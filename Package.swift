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
    ],
    dependencies: [
        // Dependencies will be added here (e.g. SwiftCurl if needed later)
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
        .testTarget(
            name: "NexusTests",
            dependencies: ["NexusApp"]),
    ]
)
