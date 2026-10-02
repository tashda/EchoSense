// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "echo-sense",
    platforms: [.macOS(.v13)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "EchoSense",
            targets: ["EchoSense"]
        ),
        // Scenarios: what EchoSense (and Echo's editor) should do at a place in some SQL, as data,
        // plus a runner. Echo Labs shows them one by one; tests in this package and in Echo run them all.
        .library(
            name: "EchoSenseScenarios",
            targets: ["EchoSenseScenarios"]
        ),
        .executable(name: "echosense-scenarios", targets: ["EchoSenseScenarioCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "EchoSense",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "EchoSenseScenarios",
            dependencies: ["EchoSense"],
            resources: [.copy("Scenarios"), .copy("DomainScenarios"), .copy("Rules")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "EchoSenseScenarioCLI",
            dependencies: ["EchoSenseScenarios"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "EchoSenseScenariosTests",
            dependencies: ["EchoSenseScenarios", "EchoSense"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "EchoSenseTests",
            dependencies: ["EchoSense"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
