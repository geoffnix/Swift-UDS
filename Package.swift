// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Swift-UDS",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
        //.linux
    ],
    products: [
        .library(name: "Swift-UDS", targets: ["Swift-UDS"]),
        .library(name: "Swift-UDS-Adapter", targets: ["Swift-UDS-Adapter"]),
        .library(name: "Swift-UDS-Session", targets: ["Swift-UDS-Session"])
    ],
    dependencies: [
        // Swift-UDS
        .package(url: "https://github.com/Cornucopia-Swift/CornucopiaCore", .branch("master")),
        // Example
        .package(url: "https://github.com/Cornucopia-Swift/CornucopiaStreams", .branch("master")),
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMajor(from: "1.0.0")),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(name: "Swift-UDS", dependencies: [
            "CornucopiaCore"
        ]),
        .target(name: "Swift-UDS-Adapter", dependencies: [
            "Swift-UDS",
            "CornucopiaCore"
        ]),
        .target(name: "Swift-UDS-Session", dependencies: [
            "Swift-UDS-Adapter"
        ]),
        .executableTarget(name: "Example", dependencies: [
            "Swift-UDS-Adapter",
            "Swift-UDS-Session",
            "CornucopiaStreams",
            .product(name: "ArgumentParser", package: "swift-argument-parser")
        ]),
        .testTarget(name: "SwiftUDSTests", dependencies: [
            "CornucopiaCore",
            "Swift-UDS"
        ]),
    ]
)
