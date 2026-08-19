// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LabelMorph",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
    ],
    products: [
        .library(name: "LabelMorph", targets: ["LabelMorph"]),
    ],
    targets: [
        .target(name: "LabelMorph"),
        .testTarget(name: "LabelMorphTests", dependencies: ["LabelMorph"]),
    ]
)
