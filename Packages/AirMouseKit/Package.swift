// swift-tools-version: 6.0
import PackageDescription

let strict: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
]

let package = Package(
    name: "AirMouseKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AirMouseProtocol", targets: ["AirMouseProtocol"]),
        .library(name: "AirMouseCrypto", targets: ["AirMouseCrypto"]),
        .library(name: "AirMouseFilters", targets: ["AirMouseFilters"]),
        .library(name: "AirMouseCore", targets: ["AirMouseCore"]),
        .executable(name: "airmouse-cli", targets: ["airmouse-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        // Layer 0 — pure data. Foundation only. No CryptoKit, no Security, no Network.
        .target(name: "AirMouseProtocol", swiftSettings: strict),

        // Layer 1a — crypto. Foundation + CryptoKit + Security + swift-certificates.
        .target(
            name: "AirMouseCrypto",
            dependencies: [
                "AirMouseProtocol",
                .product(name: "X509", package: "swift-certificates"),
            ],
            swiftSettings: strict
        ),

        // Layer 1b — numerics. Foundation + simd. Independent of Protocol on purpose.
        .target(name: "AirMouseFilters", swiftSettings: strict),

        // Layer 2 — platform-agnostic session logic. No Network.framework: transports are injected.
        .target(
            name: "AirMouseCore",
            dependencies: ["AirMouseProtocol", "AirMouseCrypto", "AirMouseFilters"],
            swiftSettings: strict
        ),

        // Tooling — the one place in the package that imports Network.framework.
        .executableTarget(
            name: "airmouse-cli",
            dependencies: [
                "AirMouseCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: strict
        ),

        .testTarget(name: "AirMouseProtocolTests", dependencies: ["AirMouseProtocol"], resources: [.copy("Vectors")]),
        .testTarget(name: "AirMouseCryptoTests", dependencies: ["AirMouseCrypto"], resources: [.copy("Vectors")]),
        .testTarget(name: "AirMouseFiltersTests", dependencies: ["AirMouseFilters"], resources: [.copy("Vectors")]),
        .testTarget(name: "AirMouseCoreTests", dependencies: ["AirMouseCore"]),
    ]
)
