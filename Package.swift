// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Quiet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "quiet", targets: ["QuietMenuBar"])
    ],
    dependencies: [
        .package(url: "https://github.com/JakubMazur/lucide-icons-swift.git", from: "1.19.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.1")
    ],
    targets: [
        .executableTarget(
            name: "QuietMenuBar",
            dependencies: [
                .product(name: "LucideIcons", package: "lucide-icons-swift"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
