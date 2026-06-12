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
        .package(url: "https://github.com/apple/swift-markdown.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "OuroMD",
            dependencies: [
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
            dependencies: ["OuroMD"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
