// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Numbers",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "Numbers",
            dependencies: [
                .product(name: "KeelTUI", package: "keel-tui")
            ])
    ]
)
