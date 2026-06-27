// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ouro-md",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ouro-md", targets: ["OuroMD"])
    ],
    dependencies: [
        .package(url: "https://github.com/ourostack/ouro-native-apple-app-shell.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-markdown.git", branch: "main")
    ],
    targets: [
        .target(
            name: "OuroMDCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "OuroMD",
            dependencies: [
                "OuroMDCore",
                .product(name: "OuroAppShellAppKit", package: "ouro-native-apple-app-shell"),
                .product(name: "OuroAppShellCore", package: "ouro-native-apple-app-shell"),
                .product(name: "OuroAppShellUI", package: "ouro-native-apple-app-shell"),
                .product(name: "Markdown", package: "swift-markdown")
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
            dependencies: ["OuroMD", "OuroMDCore"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
