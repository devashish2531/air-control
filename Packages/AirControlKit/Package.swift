// swift-tools-version: 6.0
import PackageDescription

let strict: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
]

let package = Package(
    name: "AirControlKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AirControlProtocol", targets: ["AirControlProtocol"]),
        .library(name: "AirControlCrypto", targets: ["AirControlCrypto"]),
        .library(name: "AirControlFilters", targets: ["AirControlFilters"]),
        .library(name: "AirControlCore", targets: ["AirControlCore"]),
        .executable(name: "aircontrol-cli", targets: ["aircontrol-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        // Layer 0 — pure data. Foundation only. No CryptoKit, no Security, no Network.
        .target(name: "AirControlProtocol", swiftSettings: strict),

        // Layer 1a — crypto. Foundation + CryptoKit + Security + swift-certificates.
        .target(
            name: "AirControlCrypto",
            dependencies: [
                "AirControlProtocol",
                .product(name: "X509", package: "swift-certificates"),
            ],
            swiftSettings: strict
        ),

        // Layer 1b — numerics. Foundation + simd. Independent of Protocol on purpose.
        .target(name: "AirControlFilters", swiftSettings: strict),

        // Layer 2 — platform-agnostic session logic. No Network.framework: transports are injected.
        .target(
            name: "AirControlCore",
            dependencies: ["AirControlProtocol", "AirControlCrypto", "AirControlFilters"],
            swiftSettings: strict
        ),

        // Tooling — the one place in the package that imports Network.framework.
        .executableTarget(
            name: "aircontrol-cli",
            dependencies: [
                "AirControlCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: strict
        ),

        .testTarget(name: "AirControlProtocolTests", dependencies: ["AirControlProtocol"], resources: [.copy("Vectors")]),
        .testTarget(name: "AirControlCryptoTests", dependencies: ["AirControlCrypto"], resources: [.copy("Vectors")]),
        .testTarget(name: "AirControlFiltersTests", dependencies: ["AirControlFilters"], resources: [.copy("Vectors")]),
        .testTarget(name: "AirControlCoreTests", dependencies: ["AirControlCore"]),
    ]
)
