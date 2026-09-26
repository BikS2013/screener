// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Screener",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Screener",
            path: "Sources/Screener",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "ScreenerTests",
            dependencies: ["Screener"],
            path: "Tests/ScreenerTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
