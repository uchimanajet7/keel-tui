// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "KeelTUI",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "KeelTUI",
            targets: ["KeelTUI"]),
    ],
    dependencies: [
         .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "KeelTUI",
            dependencies: []),
        .testTarget(
            name: "KeelTUITests",
            dependencies: ["KeelTUI"]),
    ]
)
