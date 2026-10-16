// swift-tools-version: 6.4
import PackageDescription
import CompilerPluginSupport

let applePlatforms: [Platform] = [.macOS, .iOS, .tvOS, .watchOS, .visionOS, .macCatalyst]

let package = Package(
    name: "swift-typesafe",
    platforms: [.macOS(.v26), .iOS(.v26), .tvOS(.v26), .watchOS(.v26), .visionOS(.v26)],
    products: [.library(name: "TypeSafe", targets: ["TypeSafe"])],
    traits: [
        .trait(
            name: "URLSession",
            description: "Back the default transport with URLSessionHTTPClient on Apple platforms. Linux falls back to AsyncHTTPClient."
        ),
        .trait(
            name: "AsyncHTTPClient",
            description: "Back the default transport with AsyncHTTPClient on every platform. Takes precedence over URLSession."
        ),
        .default(enabledTraits: ["URLSession"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-http-api-proposal.git", exact: "0.2.1"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.15.1"),
        .package(url: "https://github.com/facebook/zstd.git", exact: "1.5.7"),
        // The pinned HTTP API uses the 1.6 container preview APIs with OS 26 support.
        .package(url: "https://github.com/apple/swift-collections.git", exact: "1.6.0"),
    ],
    targets: [
        .macro(name: "TypeSafeMacros", dependencies: [
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        ]),
        .target(name: "TypeSafe", dependencies: [
            "TypeSafeMacros",
            .product(name: "BasicContainers", package: "swift-collections"),
            .product(name: "libzstd", package: "zstd"),
            // Depend on the backends directly: the proposal's HTTPClient product compiles both of them.
            .product(name: "HTTPAPIs", package: "swift-http-api-proposal"),
            .product(
                name: "URLSessionHTTPClient", package: "swift-http-api-proposal",
                condition: .when(platforms: applePlatforms, traits: ["URLSession"])
            ),
            .product(
                name: "AHCHTTPClient", package: "swift-http-api-proposal",
                condition: .when(traits: ["AsyncHTTPClient"])
            ),
            // URLSessionHTTPClient is Darwin-only, so Linux needs AsyncHTTPClient under the default trait.
            .product(
                name: "AHCHTTPClient", package: "swift-http-api-proposal",
                condition: .when(platforms: [.linux], traits: ["URLSession"])
            ),
            .product(name: "Logging", package: "swift-log"),
        ]),
        .testTarget(name: "TypeSafeTests", dependencies: ["TypeSafe", .product(name: "libzstd", package: "zstd")], exclude: ["Support"]),
        .testTarget(name: "TypeSafeMacrosTests", dependencies: [
            "TypeSafeMacros",
            .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
        ]),
    ]
)
