// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BatteryMeter",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "BatteryMeterCore"),
        .executableTarget(name: "BatteryMeter", dependencies: ["BatteryMeterCore"]),
        .testTarget(name: "BatteryMeterCoreTests", dependencies: ["BatteryMeterCore"]),
    ],
    swiftLanguageModes: [.v5]
)
