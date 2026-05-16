// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HelloWorld",
    products: [
        .executable(name: "App", targets: ["App"]),
    ],
    dependencies: [
        // Local path back to the parent Swiflow package.
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "SwiflowWeb", package: "Swiflow"),
            ],
            path: "Sources/App"
        ),
    ]
)
