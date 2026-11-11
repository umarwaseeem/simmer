// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Simmer",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SimmerShared", targets: ["SimmerShared"]),
        .executable(name: "simmerd", targets: ["simmerd"]),
        .executable(name: "simmerctl", targets: ["simmerctl"]),
    ],
    targets: [
        .target(name: "SimmerShared", path: "Sources/SimmerShared"),
        .executableTarget(name: "simmerd", dependencies: ["SimmerShared"], path: "Sources/simmerd"),
        .executableTarget(name: "simmerctl", dependencies: ["SimmerShared"], path: "Sources/simmerctl"),
        .testTarget(name: "SimmerTests", dependencies: ["SimmerShared"], path: "Tests/SimmerTests"),
    ]
)
