// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Colors",
    platforms: [
        .macOS(.v26),
    ],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "Colors",
            dependencies: [
                .product(name: "KeelTUI", package: "keel-tui")
            ]
        ),
    ]
)
