//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Whether this Xcode's `simctl` would first run `xcodebuild -runFirstLaunch` — which waits on an administrator password nobody is shown — and the evidence that a stalled call was waiting there (SimWalk#136).
///
/// An Xcode's `simctl` can be a script rather than the tool: it reads the installed CoreSimulator's `CFBundleVersion`, and when that is missing or older than the version the script names in `EXPECTED_VERSION="…"`, runs `xcodebuild -runFirstLaunch` before every call. Measured on Xcode 27.1: a walk booted its device and then sat behind the password prompt in `simctl ui … appearance`, printing nothing.
public struct XcodeFirstLaunch {
    /// What every `simctl` call does first on such a machine, and why it never returns on its own.
    static var cause: String {
        "every simctl call first runs `xcodebuild -runFirstLaunch`, which waits on an administrator password"
    }

    /// What ends it.
    static var fix: String {
        "run `sudo xcodebuild -runFirstLaunch` (or open Xcode once), then retry"
    }

    /// The `Info.plist` the `simctl` script reads the installed CoreSimulator's version from.
    public static var coreSimulatorInfo: URL {
        URL(fileURLWithPath: "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/Info.plist")
    }

    /// Refuses, before anything touches a device, when the `simctl` that `xcrun` would run is a script that would first run `xcodebuild -runFirstLaunch` — naming both versions, the cause and the fix.
    ///
    /// It refuses only on what it can read. A `simctl` that is a binary, a script with no `EXPECTED_VERSION` line, a version that does not parse, or an `xcrun` that cannot say where `simctl` is all pass: the bound on every `simctl` call (``SimctlBound``) still catches a stall, and the timeout names its cause when the stalled tree shows it. `xcrun` and `coreSimulatorInfo` are the seams a test points at a stub.
    public static func preflight(shell: Shell, xcrun: String = "/usr/bin/xcrun", coreSimulatorInfo: URL = Self.coreSimulatorInfo) throws {
        guard let found = try? shell.run(xcrun, ["--find", "simctl"], timeout: 10), found.succeeded, !found.truncated else { return }
        let simctl = found.standardOutput.trimmed
        guard !simctl.isEmpty, let expected = expectedVersion(inScriptAt: URL(fileURLWithPath: simctl)) else { return }
        let installed = installedVersion(at: coreSimulatorInfo)
        guard isPending(installed: installed, expected: expected) == true else { return }
        throw XcodeFirstLaunchError.pending(installed: installed, expected: expected)
    }

    /// Whether the `simctl` script would run `xcodebuild -runFirstLaunch`, by its own rule.
    ///
    /// That is an `installed` version that is missing or empty, or older than `expected` once trailing `.0` components are stripped from both. `nil` when either version does not parse, which refuses nothing.
    static func isPending(installed: String?, expected: String) -> Bool? {
        guard let wanted = components(of: expected) else { return nil }
        guard let installed, !installed.trimmed.isEmpty else { return true }
        guard let have = components(of: installed) else { return nil }
        return have.lexicographicallyPrecedes(wanted)
    }

    /// The `EXPECTED_VERSION="…"` a `simctl` script at `url` names; `nil` for a binary, an unreadable file or a script that names none.
    static func expectedVersion(inScriptAt url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // A script is short, and a binary is refused on its first two bytes; nothing past the first 64 KB is read either way.
        guard let head = try? handle.read(upToCount: 65536), head.starts(with: Data("#!".utf8)) else { return nil }
        return expectedVersion(inScript: String(decoding: head, as: UTF8.self))
    }

    /// The value of the script's `EXPECTED_VERSION=` line, quoted or not; `nil` when there is none or it is empty.
    static func expectedVersion(inScript text: String) -> String? {
        let key = "EXPECTED_VERSION="
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(key) else { continue }
            let value = trimmed.dropFirst(key.count).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Whether any of `commandLines` is `xcodebuild -runFirstLaunch` — an `xcodebuild` named by its path's last component, with the flag after it, so a script run as `sh …/xcodebuild -runFirstLaunch` counts as the tool does.
    static func isWaiting(in commandLines: [[String]]) -> Bool {
        commandLines.contains { arguments in
            guard let tool = arguments.firstIndex(where: { URL(fileURLWithPath: $0).lastPathComponent == "xcodebuild" }) else { return false }
            return arguments[(tool + 1)...].contains("-runFirstLaunch")
        }
    }

    /// The installed CoreSimulator's `CFBundleVersion`, read in-process; `nil` when the file or the key is not there.
    private static func installedVersion(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return nil
        }
        return plist["CFBundleVersion"] as? String
    }

    /// A version's numeric components with trailing zeros stripped, as the script canonicalises it; `nil` for anything but dot-separated digits.
    private static func components(of version: String) -> [Int]? {
        let parts = version.trimmed.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { $0.allSatisfy(\.isASCII) ? Int($0) : nil }
        guard !parts.isEmpty, numbers.count == parts.count else { return nil }
        return Array(numbers.reversed().drop { $0 == 0 }.reversed())
    }
}

public extension XcodeFirstLaunch {
    /// The preflight as one command makes it: before that command's first `simctl` call, whichever path reaches one first, and at most once (SimWalk#136).
    ///
    /// A command reaches `simctl` by more than one path — a `--device` is looked up in `simctl list` before the simulator path takes the device — so each site that is about to make a command's first call asks this, and only the first ask runs the check. A path that makes no `simctl` call never asks. A class so the sites a command threads it through share the one answer.
    ///
    /// `xcrun` and `coreSimulatorInfo` are the seams a test points at a stub, so a command-level test can make the preflight refuse.
    final class Check {
        let xcrun: String
        let coreSimulatorInfo: URL
        private var passed = false

        public init(xcrun: String = "/usr/bin/xcrun", coreSimulatorInfo: URL = XcodeFirstLaunch.coreSimulatorInfo) {
            self.xcrun = xcrun
            self.coreSimulatorInfo = coreSimulatorInfo
        }

        /// ``XcodeFirstLaunch/preflight(shell:xcrun:coreSimulatorInfo:)``, unless this command's check has already passed.
        public func preflight(shell: Shell) throws {
            guard !passed else { return }
            try XcodeFirstLaunch.preflight(shell: shell, xcrun: xcrun, coreSimulatorInfo: coreSimulatorInfo)
            passed = true
        }
    }
}
