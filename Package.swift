// swift-tools-version: 6.2
//
// Copyright © Agulhas Labs
//
import PackageDescription

/// Swift 6 language mode + zero-warning builds for every target.
///
/// Unlike a shared library, this package is never consumed by an Xcode app as an external dependency, so
/// `.treatAllWarnings(as: .error)` is safe to set in the manifest itself.
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "SimWalk",
    // A dev tool that must run anywhere it is pointed at a simulator — including machines that trail the
    // latest OS — so the floor stays low, matching Sift.
    //
    // **iOS is not decoration.** The capture bundle is the contract on both sides of the runner boundary
    // (Brief §5), and the write side executes *inside the XCUITest process on the simulator* — so
    // `SimWalkCore` has to link into an iOS target or the runner would need its own copy of the writer,
    // which is the second speller the whole layout rule exists to prevent.
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(
            name: "SimWalkCore",
            targets: ["SimWalkCore"]
        ),
        .executable(
            name: "simwalk",
            targets: ["SimWalkCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "SimWalkCore",
            swiftSettings: strictSettings
        ),
        // Orchestration: everything that spawns `simctl` and `xcodebuild`. Separate from the core
        // because it is **host-only by nature** — `Process` does not exist on iOS — and the core has to
        // build for the simulator, where the bundle's write side executes. Splitting by target rather
        // than by `#if` keeps that boundary a fact about dependencies instead of a fact scattered
        // through files, and keeps `SimWalkCore` the pure contract layer the portability rule requires.
        .target(
            name: "SimWalkDriver",
            dependencies: [
                "SimWalkCore",
            ],
            swiftSettings: strictSettings
        ),
        .target(
            name: "SimWalkMCP",
            dependencies: [
                "SimWalkCore",
            ],
            swiftSettings: strictSettings
        ),
        .executableTarget(
            name: "SimWalkCLI",
            dependencies: [
                "SimWalkCore",
                "SimWalkDriver",
                "SimWalkMCP",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: strictSettings
        ),
        // Both test targets write real scratch directories, and both write real capture bundles into
        // them. The helper that makes and reaps a directory, and the one that writes a bundle, are a
        // target rather than a copy per suite: a fix to the cleanup lands once, and a bundle built two
        // ways would be two answers to the one thing every reader in this package agrees on.
        .target(
            name: "SimWalkTestSupport",
            dependencies: [
                "SimWalkCore",
                // The live session's fake runner process stands in for the driver's own protocol.
                "SimWalkDriver",
            ],
            path: "Tests/SimWalkTestSupport",
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "SimWalkCoreTests",
            dependencies: [
                "SimWalkCore",
                "SimWalkTestSupport",
            ],
            // Walkbooks are data files (Brief §7.1), so a field walk is a committed fixture read
            // from disk rather than a Swift literal — the test then exercises the real load path.
            resources: [
                .copy("Fixtures"),
            ],
            swiftSettings: strictSettings
        ),
        // The orchestration layer reads child processes and simctl's JSON, both of which are other
        // people's formats: parsing is checkable here, spawning is checkable against real commands.
        .testTarget(
            name: "SimWalkDriverTests",
            dependencies: [
                "SimWalkDriver",
                "SimWalkCore",
                "SimWalkTestSupport",
            ],
            // The value oracle's test double is a real script, run as a walkbook's oracle command is.
            resources: [
                .copy("Fixtures"),
            ],
            swiftSettings: strictSettings
        ),
        // The agent-facing contract: a wire protocol, a status-line segment somebody reads at a glance,
        // and writes into another tool's configuration files. Every one of those is a shape a caller
        // depends on and none of them is checkable by reading the code that produces it.
        .testTarget(
            name: "SimWalkMCPTests",
            dependencies: [
                "SimWalkMCP",
                "SimWalkCore",
                "SimWalkTestSupport",
            ],
            swiftSettings: strictSettings
        ),
        // The CLI's contract — which stream, which exit code, which log line — is only checkable
        // against the face itself, so the executable target is tested rather than trusted.
        .testTarget(
            name: "SimWalkCLITests",
            dependencies: [
                "SimWalkCLI",
                "SimWalkCore",
                // The driver's own errors, because one of the CLI's contracts is what it does with a
                // runner failure: hold it, read the bundle anyway, and answer with the runner's error
                // only when there is no bundle. Asserting that against a stand-in error would check the
                // shape of the decision and not the thing it is made of.
                "SimWalkDriver",
                // The MCP face's own end of the wiring: the server is handed the CLI's commands, and
                // "the two faces answer alike" is only checkable where both of them are in scope.
                "SimWalkMCP",
                "SimWalkTestSupport",
            ],
            swiftSettings: strictSettings
        ),
    ]
)
