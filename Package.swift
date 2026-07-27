// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Era",
    platforms: [.iOS(.v18)],
    products: [
        .executable(
            name: "Era",
            targets: ["Era"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Era",
            dependencies: [],
            path: "Sources/Era",
            exclude: [".github"]
        )
    ]
)
