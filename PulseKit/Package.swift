// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PulseKit",
    platforms: [.macOS("26.0")],
    products: [.library(name: "PulseKit", targets: ["PulseKit"])],
    targets: [
        .target(name: "PulseKit"),
        .testTarget(name: "PulseKitTests", dependencies: ["PulseKit"], resources: [.copy("Fixtures")]),
    ]
)
