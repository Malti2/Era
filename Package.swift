// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Era",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .iOSApplication(
            name: "Era",
            targets: ["Era"],
            bundleIdentifier: "com.malti2.era",
            teamIdentifier: "YOUR_TEAM_ID",
            displayVersion: "1.0",
            bundleVersion: "1",
            appCategory: .music,
            supportedDeviceFamilies: [.phone, .pad],
            buildSettings: .init(
                infoPlist: [
                    "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"]
                ]
            )
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Era",
            path: "Sources/Era",
            resources: []
        )
    ]
)
