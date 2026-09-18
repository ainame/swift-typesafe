// swift-tools-version: 6.4
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "TypeSafe",
    platforms: [.macOS(.v26), .iOS(.v26), .tvOS(.v26), .watchOS(.v26), .visionOS(.v26)],
    products: [.library(name: "TypeSafe", targets: ["TypeSafe"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-http-api-proposal.git", exact: "0.2.1"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.15.1"),
    ],
    targets: [
        .macro(name: "TypeSafeMacros", dependencies: [
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        ]),
        .target(name: "TypeSafe", dependencies: [
            "TypeSafeMacros",
            .product(name: "HTTPClient", package: "swift-http-api-proposal"),
            .product(name: "Logging", package: "swift-log"),
        ]),
        .testTarget(name: "TypeSafeTests", dependencies: ["TypeSafe"], exclude: ["Support"]),
        .testTarget(name: "TypeSafeMacrosTests", dependencies: [
            "TypeSafeMacros",
            .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
        ]),
    ]
)
