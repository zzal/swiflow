// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Swiflow",
    products: [
        .library(name: "Swiflow", targets: ["Swiflow"]),
    ],
    targets: [
        .target(
            name: "Swiflow",
            path: "Sources/Swiflow"
        ),
        .testTarget(
            name: "SwiflowTests",
            dependencies: ["Swiflow"],
            path: "Tests/SwiflowTests"
        ),
    ]
)
