// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Trackie",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Trackie", targets: ["Trackie"]),
        // Product name intentionally distinct from "Trackie" because macOS is
        // case-insensitive — two binaries whose names differ only in case
        // overwrite each other in the shared build folder. `build-app.sh`
        // installs this as `trackie` on the user's PATH.
        .executable(name: "trackiectl", targets: ["TrackieCLI"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TrackieClient",
            path: "Sources/TrackieClient"
        ),
        .executableTarget(
            name: "Trackie",
            dependencies: ["TrackieClient"],
            path: "Sources/TrackieApp",
            exclude: ["Info.plist", "Trackie.entitlements"],
            resources: [
                .process("Assets.xcassets"),
                .copy("Resources")
            ]
        ),
        .executableTarget(
            name: "TrackieCLI",
            dependencies: ["TrackieClient"],
            path: "Sources/TrackieCLI"
        ),
        .testTarget(
            name: "TrackieTests",
            dependencies: ["TrackieClient"],
            path: "Tests/TrackieTests"
        )
    ]
)
