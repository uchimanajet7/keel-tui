// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Scrolling",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "../../")],
    targets: [
        .executableTarget(name: "Scrolling", dependencies: [
            .product(name: "KeelTUI", package: "keel-tui")
        ])
    ]
)
