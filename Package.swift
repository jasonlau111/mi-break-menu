// swift-tools-version: 6.3
import PackageDescription
let package = Package(
    name: "MiBreak", platforms: [.macOS(.v14)],
    products: [.library(name: "BreakCore", targets: ["BreakCore"]), .executable(name: "MiBreak", targets: ["MiBreak"])],
    dependencies: [.package(url: "https://github.com/Ebullioscopic/AtollRPC.git", revision: "d6005a8a522f19d155d31cff872099ea8095f9dc")],
    targets: [
        .target(name: "BreakCore", path: "Timing"),
        .executableTarget(name: "MiBreak", dependencies: ["BreakCore", .product(name: "AtollRPC", package: "AtollRPC")], path: "Sources", swiftSettings: [.defaultIsolation(MainActor.self), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
        .testTarget(name: "BreakCoreTests", dependencies: ["BreakCore"])
    ])
