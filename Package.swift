// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwitchLoader",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SwitchLoader", targets: ["SwitchLoaderApp"]),
        .library(name: "SwitchLoaderCore", targets: ["SwitchLoaderCore"])
    ],
    targets: [
        .executableTarget(
            name: "SwitchLoaderApp",
            dependencies: ["SwitchLoaderCore"]
        ),
        .target(
            name: "SwitchLoaderCore",
            dependencies: ["CLibUSB"]
        ),
        .systemLibrary(
            name: "CLibUSB",
            pkgConfig: "libusb-1.0",
            providers: [
                .brew(["libusb"])
            ]
        ),
        .testTarget(
            name: "SwitchLoaderCoreTests",
            dependencies: ["SwitchLoaderCore"]
        )
    ]
)
