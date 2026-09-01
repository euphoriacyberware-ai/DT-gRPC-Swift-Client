// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DrawThingsClient",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "DrawThingsClient",
            targets: ["DrawThingsClient"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.23.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.27.0"),
        .package(url: "https://github.com/google/flatbuffers.git", exact: "25.9.23"),
    ],
    targets: [
        .target(
            name: "CFpzip",
            path: "Sources/CFpzip",
            exclude: [
                "LICENSE",
                "src/CMakeLists.txt",
                "src/Makefile",
                "src/fpe.inl",
                "src/pccodec.inl",
                "src/pcdecoder.inl",
                "src/pcencoder.inl",
                "src/pcmap.inl",
                "src/rcdecoder.inl",
                "src/rcencoder.inl",
                "src/rcqsmodel.inl",
            ],
            sources: ["src"],
            publicHeadersPath: "include",
            cxxSettings: [
                .define("FPZIP_FP", to: "FPZIP_FP_FAST"),
                .define("FPZIP_BLOCK_SIZE", to: "0x1000"),
                .headerSearchPath("src"),
                .headerSearchPath("include"),
                .unsafeFlags(["-std=c++98", "-fPIC"]),
            ]
        ),
        .target(
            name: "DrawThingsClient",
            dependencies: [
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "FlatBuffers", package: "flatbuffers"),
                "CFpzip",
            ],
            resources: [
                .copy("Resources/models.json"),
            ]
        ),
        .testTarget(
            name: "DrawThingsClientTests",
            dependencies: ["DrawThingsClient"]
        ),
    ],
    cxxLanguageStandard: .cxx11
)
