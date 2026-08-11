// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GameLog",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "GameLog", targets: ["GameLog"])
    ],
    targets: [
        .executableTarget(
            name: "GameLog",
            path: "Sources/GameLog",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "GameLogTests",
            dependencies: ["GameLog"],
            path: "Tests/GameLogTests"
        )
    ]
)
