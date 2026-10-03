// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HyperMac",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "HyperMac", targets: ["HyperMac"])],
    targets: [
        .target(name: "HyperMacCore"),
        .executableTarget(name: "HyperMac", dependencies: ["HyperMacCore"]),
        .testTarget(name: "HyperMacCoreTests", dependencies: ["HyperMacCore"])
    ],
    swiftLanguageVersions: [.v5]
)
