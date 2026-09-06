// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ash",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Ash", targets: ["Ash"])],
    dependencies: [.package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.20.0")],
    targets: [
        .executableTarget(name: "Ash", dependencies: ["SwiftTerm"], path: "Sources/Ash",
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "AshTests", dependencies: ["Ash"], path: "tests/AshTests")
    ]
)
