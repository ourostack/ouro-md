// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ouro-md",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "ouro-md", targets: ["OuroMD"])
    ],
    dependencies: [
        .package(url: "https://github.com/ourostack/ouro-native-apple-app-shell.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-markdown.git", revision: "4661b550c55abde97d14e35b89e094084669f40a"),
        // Ouro AX for Apple: outcomes, problems and entity matching for the App Intents and the MCP door.
        .package(url: "https://github.com/ourostack/ouro-ui-apple.git", .upToNextMinor(from: "0.4.1"))
    ],
    targets: [
        .target(
            name: "OuroMDCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .target(
            name: "OuroMDAppSupport",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "OuroMD",
            dependencies: [
                "OuroMDAppSupport",
                "OuroMDCore",
                .product(name: "OuroAppShellAppKit", package: "ouro-native-apple-app-shell"),
                .product(name: "OuroAppShellContract", package: "ouro-native-apple-app-shell"),
                .product(name: "OuroAppShellCore", package: "ouro-native-apple-app-shell"),
                .product(name: "OuroAppShellUI", package: "ouro-native-apple-app-shell"),
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "OuroAX", package: "ouro-ui-apple"),
                .product(name: "OuroHX", package: "ouro-ui-apple")
            ],
            resources: [
                .copy("web")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "OuroMDTests",
            dependencies: [
                "OuroMD",
                "OuroMDAppSupport",
                "OuroMDCore",
                .product(name: "OuroAppShellConsumerTesting", package: "ouro-native-apple-app-shell")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "OuroMDAppSupportTests",
            dependencies: [
                "OuroMDAppSupport"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
