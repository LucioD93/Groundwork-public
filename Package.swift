// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Groundwork", platforms: [.macOS(.v13), .iOS(.v17)], products: [.library(name: "GroundsCore", targets: ["GroundsCore"])], targets: [.systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"), .target(name: "GroundsCore", dependencies: ["CSQLite"]), .executableTarget(name: "VerifyJournal", dependencies: ["GroundsCore"], path: "Verification"), .testTarget(name: "GroundsCoreTests", dependencies: ["GroundsCore"])])
