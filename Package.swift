// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FanCtl",
    platforms: [.macOS(.v13)],
    targets: [
        // Raw AppleSMC user-client calls (C keeps the 80-byte struct layout exact).
        .target(
            name: "CSMC",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // Typed key read/write, fan + temperature helpers, shared protocol constants.
        .target(name: "SMCKit", dependencies: ["CSMC"]),
        // Root helper: the only process that writes to the SMC.
        .executableTarget(name: "fanctld", dependencies: ["SMCKit"]),
        // Menu-bar UI: reads sensors directly, asks fanctld to change fans.
        .executableTarget(name: "FanCtl", dependencies: ["SMCKit"]),
    ]
)
