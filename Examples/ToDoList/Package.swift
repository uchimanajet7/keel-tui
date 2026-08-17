// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "ToDoList",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "ToDoList",
            dependencies: [
                .product(name: "KeelTUI", package: "keel-tui")
            ])
    ]
)
