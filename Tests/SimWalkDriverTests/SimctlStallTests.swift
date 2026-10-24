//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkDriver
import Testing

/// SimWalk#136: a `simctl` call that stalls is stopped at its bound and refused naming the command — and the cause, only where the stalled tree shows `xcodebuild -runFirstLaunch`.
///
/// Each stub is a real blocking process, so the evidence is read the way a real stall's is.
///
/// The stubs run only `/bin/sh` and `/bin/sleep`, never git.
struct SimctlStallTests {
    /// The stall measured on Xcode 27.1: `simctl` is a script that first runs `xcodebuild -runFirstLaunch`, which never returns.
    @Test
    func aSimctlCallStalledBehindFirstLaunchIsRefusedNamingTheCommandTheCauseAndTheFix() throws {
        let stub = try StubXcrun(waitingOnFirstLaunch: true)
        defer { stub.remove() }

        // The evidence is injected because the real tree's timing under load is the flake (SimWalk#164); the next test reads the real tree.
        let firstLaunch = [stub.directory.appendingPathComponent("xcodebuild").path, "-runFirstLaunch"]
        let readAtStop = ReadTree()
        let shell = Shell { root, group in
            let real = ProcessTree.commandLines(of: root, group: group)
            readAtStop.record(real)
            return real + [firstLaunch]
        }
        let error = #expect(throws: ShellError.self) {
            try shell.run(stub.xcrun, ["simctl", "ui", "UDID-1", "appearance"], timeout: 0.5)
        }

        // The tree is read before the stop (SimWalk#136): the stalled call's root is still alive when it is read.
        #expect(readAtStop.lines.contains { $0.contains(stub.xcrun) }, "command lines read: \(readAtStop.lines)")
        #expect(error == .stalledOnFirstLaunch(command: "xcrun simctl ui UDID-1 appearance", seconds: 0.5))
        let text = error.map { String(describing: $0) } ?? ""
        #expect(text.contains("`xcrun simctl ui UDID-1 appearance` did not finish within"))
        #expect(text.contains("`xcodebuild -runFirstLaunch`, which waits on an administrator password"))
        #expect(text.contains("run `sudo xcodebuild -runFirstLaunch` (or open Xcode once)"))
        #expect(stub.processesLeft().isEmpty)
    }

    /// The real tree is read: a stub chain waiting on first launch shows `xcodebuild -runFirstLaunch` under the process the call started.
    @Test
    func theRealProcessTreeOfAStalledCallShowsFirstLaunch() throws {
        let stub = try StubXcrun(waitingOnFirstLaunch: true)
        defer { stub.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: stub.xcrun)
        process.arguments = ["simctl", "ui", "UDID-1", "appearance"]
        try process.run()
        let pid = process.processIdentifier
        var stopped = false
        defer {
            if !stopped {
                kill(-pid, SIGKILL)
                process.waitUntilExit()
            }
        }

        var lines: [[String]] = []
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            lines = ProcessTree.commandLines(of: pid, group: pid)
            if XcodeFirstLaunch.isWaiting(in: lines) {
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        #expect(XcodeFirstLaunch.isWaiting(in: lines), "last command lines read: \(lines)")
        stopped = true
        kill(-pid, SIGKILL)
        process.waitUntilExit()
        #expect(stub.processesLeft().isEmpty)
    }

    /// A stall with nothing in its tree to say why is refused naming the command alone: a cause is claimed only on evidence.
    @Test
    func aSimctlCallStalledForNoVisibleReasonIsRefusedNamingOnlyTheCommand() throws {
        let stub = try StubXcrun(waitingOnFirstLaunch: false)
        defer { stub.remove() }

        let error = #expect(throws: ShellError.self) {
            try Shell().run(stub.xcrun, ["simctl", "ui", "UDID-1", "appearance"], timeout: 0.5)
        }

        #expect(error == .timedOut(command: "xcrun simctl ui UDID-1 appearance", seconds: 0.5))
        #expect(error.map { String(describing: $0) }?.contains("runFirstLaunch") == false)
        #expect(stub.processesLeft().isEmpty)
    }

    /// The preflight, end to end against a stub `xcrun` and a stub CoreSimulator `Info.plist`: an older CoreSimulator refuses naming both versions; the expected one passes.
    @Test
    func thePreflightRefusesAnOlderCoreSimulatorAndPassesTheExpectedOne() throws {
        let stub = try StubXcrun(waitingOnFirstLaunch: true)
        defer { stub.remove() }
        let older = try stub.coreSimulatorInfo(version: "1174.8")
        let expected = try stub.coreSimulatorInfo(version: "1174.9.2.0")

        let error = #expect(throws: XcodeFirstLaunchError.self) {
            try XcodeFirstLaunch.preflight(shell: Shell(), xcrun: stub.xcrun, coreSimulatorInfo: older)
        }

        #expect(error == .pending(installed: "1174.8", expected: "1174.9.2"))
        #expect(throws: Never.self) { try XcodeFirstLaunch.preflight(shell: Shell(), xcrun: stub.xcrun, coreSimulatorInfo: expected) }
        // No version to read is what makes the script run it too.
        #expect(throws: XcodeFirstLaunchError.pending(installed: nil, expected: "1174.9.2")) {
            try XcodeFirstLaunch.preflight(shell: Shell(), xcrun: stub.xcrun, coreSimulatorInfo: stub.directory.appendingPathComponent("absent.plist"))
        }
    }
}

extension SimctlStallTests {
    /// The real command lines an injected tree reader saw, kept for the test to check after the call returns.
    final class ReadTree: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [[String]] = []

        var lines: [[String]] {
            lock.withLock { recorded }
        }

        func record(_ lines: [[String]]) {
            lock.withLock { recorded = lines }
        }
    }

    /// A temporary directory holding an `xcrun` whose `simctl` blocks — behind a stub `xcodebuild -runFirstLaunch`, or behind a bare `sleep` — and that answers `--find simctl` with a `simctl` script naming `EXPECTED_VERSION="1174.9.2"`.
    ///
    /// Every process it starts appends its pid to `pids`.
    struct StubXcrun {
        let directory: URL

        var xcrun: String {
            directory.appendingPathComponent("xcrun").path
        }

        init(waitingOnFirstLaunch: Bool) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("simwalk-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let here = #"here="$(dirname "$0")"; echo $$ >> "$here/pids""#
            let block = #"/bin/sleep 30 & echo $! >> "$here/pids"; wait"#
            let simctl = waitingOnFirstLaunch ? #""$here/xcodebuild" -runFirstLaunch"# : block
            try write("xcrun", "#!/bin/sh\n\(here)\nif [ \"$1\" = --find ]; then echo \"$here/simctl\"; exit 0; fi\n\(simctl)\n")
            try write("xcodebuild", "#!/bin/sh\n\(here)\n\(block)\n")
            try write("simctl", "#!/bin/bash\nEXPECTED_VERSION=\"1174.9.2\"\nexit 0\n")
        }

        func coreSimulatorInfo(version: String) throws -> URL {
            let url = directory.appendingPathComponent("Info-\(version).plist")
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleVersion": version], format: .xml, options: 0).write(to: url)
            return url
        }

        /// The stub's processes still running, after giving the stopped ones a moment to be reaped.
        func processesLeft() -> [pid_t] {
            let text = (try? String(contentsOf: directory.appendingPathComponent("pids"), encoding: .utf8)) ?? ""
            let pids = text.split(separator: "\n").compactMap { pid_t($0) }
            let deadline = Date().addingTimeInterval(3)
            var alive = pids
            while !alive.isEmpty, Date() < deadline {
                alive = alive.filter { kill($0, 0) == 0 || errno != ESRCH }
                Thread.sleep(forTimeInterval: 0.05)
            }
            return alive
        }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }

        private func write(_ name: String, _ text: String) throws {
            let url = directory.appendingPathComponent(name)
            try Data(text.utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }
}
