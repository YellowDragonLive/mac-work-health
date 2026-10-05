// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VitalityWidget",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VitalityWidget",
            path: "Sources/VitalityWidget"
        )
    ]
)
