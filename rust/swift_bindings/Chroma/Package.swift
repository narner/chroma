// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.
// Swift Package: Chroma

import PackageDescription;

let package = Package(
    name: "Chroma",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "Chroma",
            targets: ["Chroma"]
        )
    ],
    dependencies: [ ],
    targets: [
        .binaryTarget(name: "ChromaFFI", path: "./ChromaFFI.xcframework"),
        .target(
            name: "Chroma",
            dependencies: [
                .target(name: "ChromaFFI")
            ]
        ),
    ]
)