// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "BailongPet", platforms: [.macOS(.v14)],
    products: [.executable(name: "BailongPet", targets: ["BailongPet"])],
    targets: [.executableTarget(name: "BailongPet", linkerSettings: [.linkedFramework("AppKit"), .linkedLibrary("sqlite3")])])
