//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkDriver
import Testing

/// SimWalk#136: the `simctl` script's own rule for running `xcodebuild -runFirstLaunch`, the line it is read from, and the evidence a stalled tree is waiting there.
struct XcodeFirstLaunchTests {
    /// Missing, empty or older runs it, by the script's comparison after trailing `.0` components are stripped; equal or newer does not; anything that does not parse refuses nothing.
    @Test(arguments: [
        Case("1174.8", "1174.9.2", true),
        Case("1174.9", "1174.9.2", true),
        Case("1100.20.5", "1174.9.2", true),
        Case(nil, "1174.9.2", true),
        Case("", "1174.9.2", true),
        Case("1174.9.2", "1174.9.2", false),
        Case("1174.9.2.0", "1174.9.2", false),
        Case("1174.9.2", "1174.9.2.0.0", false),
        Case("1174.10", "1174.9.2", false),
        Case("1175", "1174.9.2", false),
        Case("1174.9.2b", "1174.9.2", nil),
        Case("1174.8", "", nil),
        Case("1174.8", "unknown", nil),
    ])
    func whetherFirstLaunchIsPending(_ check: Case) {
        #expect(XcodeFirstLaunch.isPending(installed: check.installed, expected: check.expected) == check.pending)
    }

    @Test
    func theExpectedVersionIsReadFromTheScriptsOwnLine() {
        let script = "#!/bin/bash\nexport DEVELOPER_DIR=x\n\nEXPECTED_VERSION=\"1174.9.2\"\nCURRENT_VERSION=\"$(x)\"\n"

        #expect(XcodeFirstLaunch.expectedVersion(inScript: script) == "1174.9.2")
        #expect(XcodeFirstLaunch.expectedVersion(inScript: "#!/bin/sh\nexec simctl \"$@\"\n") == nil)
        #expect(XcodeFirstLaunch.expectedVersion(inScript: "#!/bin/sh\nEXPECTED_VERSION=\"\"\n") == nil)
    }

    /// A `simctl` that is a binary is never read as a script, whatever bytes it holds.
    @Test
    func aBinarySimctlNamesNoExpectedVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("simwalk-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = directory.appendingPathComponent("simctl")
        try Data([0xCF, 0xFA, 0xED, 0xFE] + Array("\nEXPECTED_VERSION=\"9999\"\n".utf8)).write(to: binary)

        #expect(XcodeFirstLaunch.expectedVersion(inScriptAt: binary) == nil)
        #expect(XcodeFirstLaunch.expectedVersion(inScriptAt: directory.appendingPathComponent("absent")) == nil)
    }

    /// The refusal names both versions, the cause and the fix, in one line.
    @Test
    func thePreflightRefusalNamesBothVersionsTheCauseAndTheFix() {
        let older = String(describing: XcodeFirstLaunchError.pending(installed: "1174.8", expected: "1174.9.2"))
        let missing = String(describing: XcodeFirstLaunchError.pending(installed: nil, expected: "1174.9.2"))

        #expect(older == "this Xcode's simctl expects CoreSimulator 1174.9.2 and 1174.8 is installed, so every simctl call first runs `xcodebuild -runFirstLaunch`, which waits on an administrator password — run `sudo xcodebuild -runFirstLaunch` (or open Xcode once), then retry")
        #expect(missing.contains("expects CoreSimulator 1174.9.2 and no installed version could be read"))
        #expect(!older.contains("\n"))
    }

    @Test
    func aTreeIsWaitingOnFirstLaunchOnlyWhenXcodebuildRunsIt() {
        #expect(XcodeFirstLaunch.isWaiting(in: [["/bin/sh", "/tmp/x/xcrun", "simctl"], ["/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild", "-runFirstLaunch"]]))
        #expect(XcodeFirstLaunch.isWaiting(in: [["/bin/sh", "/tmp/x/xcodebuild", "-runFirstLaunch"]]))
        #expect(!XcodeFirstLaunch.isWaiting(in: [["/usr/bin/xcodebuild", "-list"]]))
        #expect(!XcodeFirstLaunch.isWaiting(in: [["/bin/sh", "-c", "echo -runFirstLaunch"]]))
        #expect(!XcodeFirstLaunch.isWaiting(in: []))
    }
}

extension XcodeFirstLaunchTests {
    /// An installed version, the version the script expects, and whether the script would run first launch (`nil`: refuses nothing).
    struct Case: Sendable, CustomTestStringConvertible {
        let installed: String?
        let expected: String
        let pending: Bool?

        init(_ installed: String?, _ expected: String, _ pending: Bool?) {
            self.installed = installed
            self.expected = expected
            self.pending = pending
        }

        var testDescription: String {
            "\(installed ?? "missing") vs \(expected)"
        }
    }
}
