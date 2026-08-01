// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PieNS",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PieNS", targets: ["PieNS"]),
        .executable(name: "PieNSHelper", targets: ["PieNSHelper"]),
        .library(name: "PieNSCore", targets: ["PieNSCore"])
    ],
    targets: [
        .target(name: "PieNSCore"),
        .executableTarget(
            name: "PieNS",
            dependencies: ["PieNSCore"],
            path: "Sources/PieNSApp"
        ),
        .executableTarget(
            name: "PieNSHelper",
            dependencies: ["PieNSCore"]
        ),
        .testTarget(
            name: "PieNSCoreTests",
            dependencies: ["PieNSCore"]
        )
    ]
)
