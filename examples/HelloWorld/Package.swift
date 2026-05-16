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
        // JavaScriptKit is declared as a direct dependency so SwiftPM
        // exposes the `swift package js` (PackageToJS) plugin to this
        // package. Without it, the plugin only surfaces on the parent
        // package and can't target this example's executable.
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.53.0")),
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
