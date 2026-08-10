// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GameLog",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "GameLog", targets: ["GameLog"])
    ],
    targets: [
        .executableTarget(
            name: "GameLog",
            path: "Sources/GameLog"
        ),
        .testTarget(
            name: "GameLogTests",
            dependencies: ["GameLog"],
            path: "Tests/GameLogTests"
        )
    ]
)
