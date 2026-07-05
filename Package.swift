// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HubOS",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        .executableTarget(
            name: "HubOS",
            path: "Sources/HubOS",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
