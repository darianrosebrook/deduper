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
        .library(
            name: "DeduperUI",
            targets: ["DeduperUI"]
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
                .process("Resources")
            ]
        ),
        .target(
            name: "DeduperUI",
            dependencies: ["DeduperCore"],
            path: "Sources/DeduperUI"
        ),
        .executableTarget(
            name: "Deduper",
            dependencies: ["DeduperUI"],
            path: "Sources/DeduperApp",
            resources: [
                .process("Info.plist"),
                .process("Deduper.entitlements")
            ]
        ),
        .testTarget(
            name: "DeduperCoreTests",
            dependencies: ["DeduperCore"],
            path: "Tests/DeduperCoreTests"
        ),
    ]
)
