// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GlassGlow",
    platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .visionOS(.v1)],
    products: [
        .library(name: "GlassGlow", targets: ["GlassGlow"]),
    ],
    targets: [
        .target(name: "GlassGlow", resources: [.copy("Shaders")]),
        .testTarget(name: "GlassGlowTests", dependencies: ["GlassGlow"]),
    ]
)
