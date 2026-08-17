// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Flags",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "Flags",
            dependencies: [
                .product(name: "KeelTUI", package: "keel-tui")
            ])
    ]
)
