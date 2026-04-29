// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexCursor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CodexCursor", targets: ["CodexCursor"])
    ],
    targets: [
        .target(
            name: "AudioTapSupport",
            path: "AudioTapSupport/Sources",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "CodexCursor",
            dependencies: ["AudioTapSupport"],
            path: "app",
            swiftSettings: []
        )
    ]
)
