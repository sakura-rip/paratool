// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Paratool",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Paratool", targets: ["Paratool"])],
    targets: [
        .target(name: "ParatoolCore"),
        .executableTarget(name: "Paratool", dependencies: ["ParatoolCore"]),
        .testTarget(name: "ParatoolCoreTests", dependencies: ["ParatoolCore"])
    ]
)
