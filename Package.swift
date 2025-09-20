// swift-tools-version: 6.2
// DeduperCore - Core library for duplicate photo and video detection
// Author: @darianrosebrook

import PackageDescription

let package = Package(
    name: "DeduperCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "DeduperCore",
            targets: ["DeduperCore"]
        ),
    ],
    dependencies: [
        // No external dependencies - using only Apple frameworks
    ],
    targets: [
        .target(
            name: "DeduperCore",
            dependencies: [],
            path: "Sources/DeduperCore",
            resources: [
                .process("../../Resources")
            ]
        ),
        .testTarget(
            name: "DeduperCoreTests",
            dependencies: ["DeduperCore"],
            path: "Tests/DeduperCoreTests"
        ),
    ]
)
