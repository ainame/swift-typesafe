// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "TypeSafeExamples",
    platforms: [.macOS(.v26)],
    dependencies: [.package(name: "swift-typesafe", path: "..")],
    targets: [.executableTarget(name: "Example", dependencies: [.product(name: "TypeSafe", package: "swift-typesafe")])]
)
