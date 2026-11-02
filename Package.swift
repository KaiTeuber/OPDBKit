// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OPDBKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "OPDBKit", targets: ["OPDBKit"])
    ],
    targets: [
        .target(
            name: "OPDBKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "OPDBKitTests",
            dependencies: ["OPDBKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
