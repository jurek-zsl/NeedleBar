// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NeedleBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NeedleBarApp", targets: ["NeedleBarApp"]),
        .library(name: "NeedleBarCore", targets: ["NeedleBarCore"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "NeedleBarCore",
            dependencies: [],
            path: "Sources/NeedleBarCore"
        ),
        .executableTarget(
            name: "NeedleBarApp",
            dependencies: ["NeedleBarCore"],
            path: "Sources/NeedleBarApp",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "NeedleBarTests",
            dependencies: ["NeedleBarCore"],
            path: "Tests/NeedleBarTests"
        )
    ]
)
