// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SnipKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SnipKit", targets: ["SnipKit"])],
    targets: [
        .target(name: "SnipKit"),
        .testTarget(name: "SnipKitTests", dependencies: ["SnipKit"]),
    ]
)
