// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DrawThingsExample",
    platforms: [.macOS(.v15), .iOS(.v18)],
    dependencies: [
        // The library from this repository. In your app, use
        // .package(url: "https://github.com/euphoriacyberware-ai/DrawThings-Swift", from: "2.0.0").
        .package(name: "DrawThings-Swift", path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "DrawThingsExample",
            dependencies: [
                .product(name: "DrawThingsKit", package: "DrawThings-Swift"),
                .product(name: "DrawThingsQueue", package: "DrawThings-Swift"),
                .product(name: "DrawThingsVideoKit", package: "DrawThings-Swift"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
