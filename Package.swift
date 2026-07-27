// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Era",
    platforms: [.iOS(.v18)],
    products: [
        .library(
            name: "Era",
            targets: ["Era"]
        )
    ],
    targets: [
        .target(
            name: "Era",
            dependencies: [],
            path: ".",
            exclude: [".github"]
        )
    ]
)
