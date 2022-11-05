// swift-tools-version:5.5.0

import PackageDescription

let package = Package(
    name: "AirtableKit",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13)
    ],
    products: [
        .library(
            name: "AirtableKit",
            targets: ["AirtableKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Quick/Quick.git", .upToNextMajor(from: "3.0.0")),
        .package(url: "https://github.com/Quick/Nimble.git", .upToNextMajor(from: "8.0.1")),
        .package(url: "https://github.com/AliSoftware/OHHTTPStubs.git", .upToNextMajor(from: "9.0.0"))
    ],
    targets: [
        .target(
            name: "AirtableKit",
            dependencies: []),
        .testTarget(
            name: "AirtableKitTests",
            dependencies: ["AirtableKit", "Quick", "Nimble", .product(name: "OHHTTPStubsSwift", package: "OHHTTPStubs")],
            resources: [.copy("mocks")]),
    ]
)
