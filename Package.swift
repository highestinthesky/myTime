// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "myTime",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "myTime", targets: ["MyTimeApp"])],
    targets: [
        .target(name: "MyTimeCore"),
        .executableTarget(name: "MyTimeApp", dependencies: ["MyTimeCore"]),
        .testTarget(name: "MyTimeCoreTests", dependencies: ["MyTimeCore"]),
    ],
    swiftLanguageModes: [.v5]
)
