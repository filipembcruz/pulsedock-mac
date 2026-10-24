// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PulseDock",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PulseDock",
            path: "Sources/PulseDock",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
