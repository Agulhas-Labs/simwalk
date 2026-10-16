//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// `appBuildHash` is what makes `ScreenOutcome.buildMismatch` possible at all, so it has to change when the binary changes and not when a version string is bumped.
struct AppBuildIdentityTests {
    /// The two bundles are **identical but for the executable's bytes** — same bundle name, same declared executable, same version — so a hash taken over anything else in the bundle cannot tell them apart, and the test would pass while the property was false.
    @Test
    func theHashIsTakenOverTheExecutableRatherThanTheVersion() throws {
        let directory = try TemporaryDirectory()
        let first = try Self.app(in: directory, at: "a", executable: "binary-bytes-v1", version: "1.0")
        let second = try Self.app(in: directory, at: "b", executable: "binary-bytes-v2", version: "1.0")

        // Same authored version, different binary: the hash must separate them, because that is exactly
        // the window a walk is run in — two builds sharing a CFBundleVersion all development long.
        #expect(try AppBuildIdentity.hash(ofAppAt: first) != AppBuildIdentity.hash(ofAppAt: second))
    }

    @Test
    func adifferentVersionOverTheSameBinaryHashesTheSame() throws {
        let directory = try TemporaryDirectory()
        let first = try Self.app(in: directory, at: "a", executable: "identical", version: "1.0")
        let second = try Self.app(in: directory, at: "b", executable: "identical", version: "9.9")

        #expect(try AppBuildIdentity.hash(ofAppAt: first) == AppBuildIdentity.hash(ofAppAt: second))
    }

    @Test
    func theSameAppHashesTheSameEveryTime() throws {
        let directory = try TemporaryDirectory()
        let app = try Self.app(in: directory, at: "a", executable: "bytes", version: "1.0")

        #expect(try AppBuildIdentity.hash(ofAppAt: app) == AppBuildIdentity.hash(ofAppAt: app))
    }

    /// The executable is the one the bundle *names*, not one guessed from the directory, so an app whose product name differs from its folder still identifies.
    @Test
    func theExecutableIsTheOneTheBundleNames() throws {
        let directory = try TemporaryDirectory()
        let app = directory.url.appendingPathComponent("Renamed.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data("bytes".utf8).write(to: app.appendingPathComponent("ActualProductName"))
        try Self.plist(executable: "ActualProductName", version: "1.0").write(to: app.appendingPathComponent("Info.plist"))

        #expect(throws: Never.self) {
            try AppBuildIdentity.hash(ofAppAt: app.path)
        }
    }

    @Test
    func adirectoryThatIsNotAnAppRefusesRatherThanHashingNothing() throws {
        let directory = try TemporaryDirectory()

        #expect(throws: AppBuildIdentityError.notAnApp(path: directory.url.path)) {
            try AppBuildIdentity.hash(ofAppAt: directory.url.path)
        }
    }

    @Test
    func abundleNamingAnExecutableThatIsNotThereRefusesNamingIt() throws {
        let directory = try TemporaryDirectory()
        let app = directory.url.appendingPathComponent("Hollow.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Self.plist(executable: "Missing", version: "1.0").write(to: app.appendingPathComponent("Info.plist"))

        let thrown = try #require(#expect(throws: AppBuildIdentityError.self) {
            try AppBuildIdentity.hash(ofAppAt: app.path)
        })

        #expect(thrown.description.contains("Missing"))
    }

    /// Builds a bundle whose only variable is the executable's bytes — the bundle name and the declared executable are fixed, so two apps differ in exactly the thing under test.
    private static func app(in directory: TemporaryDirectory, at subdirectory: String, executable bytes: String, version: String) throws -> String {
        let app = directory.url.appendingPathComponent(subdirectory).appendingPathComponent("App.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data(bytes.utf8).write(to: app.appendingPathComponent("App"))
        try plist(executable: "App", version: version).write(to: app.appendingPathComponent("Info.plist"))
        return app.path
    }

    private static func plist(executable: String, version: String) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleExecutable": executable, "CFBundleVersion": version],
            format: .xml,
            options: 0
        )
    }
}
