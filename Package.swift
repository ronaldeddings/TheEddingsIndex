// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TheEddingsIndex",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(name: "EddingsKit", targets: ["EddingsKit"]),
        .executable(name: "ei-cli", targets: ["EddingsCLI"]),
        .executable(name: "TheEddingsIndex", targets: ["EddingsApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/unum-cloud/usearch", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "EddingsKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "USearch", package: "usearch"),
            ]
        ),
        .executableTarget(
            name: "EddingsCLI",
            dependencies: [
                "EddingsKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "EddingsApp",
            dependencies: ["EddingsKit"],
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "EddingsKitTests",
            dependencies: ["EddingsKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
