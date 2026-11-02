// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "LinguaMac",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LinguaMac", targets: ["LinguaMac"])],
    dependencies: [
        .package(path: "Vendor/mlx-swift"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3", traits: []),
        .package(url: "https://github.com/huggingface/swift-huggingface", exact: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.3.0"),
    ],
    targets: [
        .target(name: "TranslationCore", resources: [.copy("Resources/InterfaceStrings.json")]),
        .executableTarget(name: "LinguaMac", dependencies: [.target(name: "TranslationCore"),
            .product(name: "MLX", package: "mlx-swift"),
            .product(name: "MLXLLM", package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
            .product(name: "HuggingFace", package: "swift-huggingface"),
            .product(name: "Tokenizers", package: "swift-transformers"),
        ], resources: [.copy("Resources/AppIcon.png"), .copy("Resources/Legal")]),
        .testTarget(name: "TranslationCoreTests", dependencies: ["TranslationCore", "LinguaMac"]),
    ]
)
