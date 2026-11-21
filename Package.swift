// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "sarashina-cli",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SarashinaCore", targets: ["SarashinaCore"]),
        .executable(name: "sarashina", targets: ["SarashinaCLI"])
    ],
    targets: [
        .target(name: "SarashinaCore"),
        .executableTarget(
            name: "SarashinaCLI",
            dependencies: ["SarashinaCore"]
        ),
        .testTarget(
            name: "SarashinaCoreTests",
            dependencies: ["SarashinaCore"]
        )
    ]
)
