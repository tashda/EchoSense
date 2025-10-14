// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EchoAutocomplete",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "EchoAutocomplete",
            targets: ["EchoAutocomplete"]
        )
    ],
    targets: [
        .target(
            name: "EchoAutocomplete"
        ),
        .testTarget(
            name: "EchoAutocompleteTests",
            dependencies: ["EchoAutocomplete"]
        )
    ]
)
