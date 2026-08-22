// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "xj-AI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "xj-AI", targets: ["xj_AI"])
    ],
    targets: [
        .executableTarget(
            name: "xj_AI",
            path: "Sources/xj-AI"
        ),
        .testTarget(
            name: "xj_AITests",
            dependencies: ["xj_AI"],
            path: "Tests/xj-AITests"
        )
    ],
    swiftLanguageModes: [.v5]
)
