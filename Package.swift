// swift-tools-version: 6.3
import PackageDescription
let package = Package(name: "MiBreak", platforms: [.macOS(.v14)], products: [.library(name: "BreakCore", targets: ["BreakCore"])], targets: [.target(name: "BreakCore", path: "Timing"), .testTarget(name: "BreakCoreTests", dependencies: ["BreakCore"])])
