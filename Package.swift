// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacWidgetPerf",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MacWidgetPerf",
            path: "Sources/MacWidgetPerf",
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("IOKit")]
        )
    ]
)
