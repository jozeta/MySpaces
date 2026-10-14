// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MySpaces",
    platforms: [.macOS("27.0")],
    targets: [
        .target(name: "MySpacesCore", path: "Sources/MySpacesCore"),
        .executableTarget(name: "MySpaces", dependencies: ["MySpacesCore"], path: "Sources/MySpaces"),
        .testTarget(
            name: "MySpacesCoreTests",
            dependencies: ["MySpacesCore"],
            path: "Tests/MySpacesCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
