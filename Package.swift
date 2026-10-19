// swift-tools-version:6.0
import PackageDescription

// Swift 5 language mode: the Mach and sysctl globals the samplers read
// (mach_task_self_, vm_kernel_page_size) are not usable under Swift 6's strict
// concurrency checking.
let package = Package(
    name: "MenuBarMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MenuBarMonitor",
            path: "Sources/MenuBarMonitor",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MenuBarMonitorTests",
            dependencies: ["MenuBarMonitor"],
            path: "Tests/MenuBarMonitorTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
