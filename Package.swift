// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NTFSAccess",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NTFSAccess", targets: ["NTFSAccessApp"]),
        .library(name: "NTFSAccessCore", targets: ["NTFSAccessCore"])
    ],
    targets: [
        .target(
            name: "NTFSAccessCore",
            path: "Sources/NTFSAccessCore",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "NTFSAccessApp",
            dependencies: ["NTFSAccessCore"],
            path: "Sources/NTFSAccessApp",
            linkerSettings: [
                .linkedFramework("DiskArbitration"),
                .linkedFramework("IOKit")
            ]
        )
        // Test target intentionally commented out: the macOS Command Line Tools
        // toolchain does not ship XCTest / swift-testing. Once full Xcode is installed,
        // re-enable by uncommenting the block below.
        //
        // .testTarget(
        //     name: "NTFSAccessCoreTests",
        //     dependencies: ["NTFSAccessCore"],
        //     path: "Tests/NTFSAccessCoreTests"
        // )
    ]
)
