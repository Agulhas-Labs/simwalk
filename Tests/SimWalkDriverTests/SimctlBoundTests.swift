//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkDriver
import Testing

/// SimWalk#136: every `simctl` call is bounded by its verb unless its caller set a bound — so a call site, or a `run` closure handed down to the device steps, cannot leave it off.
struct SimctlBoundTests {
    @Test
    func everySimctlCallCarriesItsVerbsBoundAndACallersOwnWins() throws {
        var bounds: [String: TimeInterval?] = [:]
        let shell = Shell(timedScript: { _, arguments, _, timeout in
            bounds[arguments.joined(separator: " ")] = timeout
            return Shell.Result(status: 0, standardOutput: "", standardError: "")
        })

        for verb in ["list", "boot", "bootstatus", "install", "clone", "ui", "privacy", "status_bar", "shutdown", "delete", "spawn", "get_app_container"] {
            _ = try shell.run("/usr/bin/xcrun", ["simctl", verb, "UDID-1"])
        }
        _ = try shell.run("/usr/bin/xcrun", ["simctl", "shutdown", "UDID-2"], timeout: 5)
        _ = try shell.run("/usr/bin/xcrun", ["xcresulttool", "get"])
        _ = try shell.run("/bin/ps", ["-axo", "pid="])

        #expect(bounds["simctl boot UDID-1"] == 120)
        #expect(["bootstatus", "install", "clone"].allSatisfy { bounds["simctl \($0) UDID-1"] == 300 })
        #expect(["list", "ui", "privacy", "status_bar", "shutdown", "delete", "spawn", "get_app_container"].allSatisfy { bounds["simctl \($0) UDID-1"] == 60 })
        #expect(bounds["simctl shutdown UDID-2"] == 5)
        #expect(bounds["xcresulttool get"] == .some(nil))
        #expect(bounds["-axo pid="] == .some(nil))
    }

    /// The device's own calls — the list, the boot and the wait for it — are bounded through the same `Shell` they always went through.
    @Test
    func aDevicesListBootAndWaitAreBounded() throws {
        var bounds: [[String]: TimeInterval?] = [:]
        let shell = Shell(timedScript: { _, arguments, _, timeout in
            bounds[arguments] = timeout
            return Shell.Result(status: 0, standardOutput: #"{"devices":{}}"#, standardError: "")
        })

        _ = try Simulator.available(shell: shell)
        try Simulator(udid: "UDID-1", name: "iPhone", osVersion: "26.5", isBooted: false).boot(shell: shell)

        #expect(bounds[["simctl", "list", "devices", "available", "--json"]] == 60)
        #expect(bounds[["simctl", "boot", "UDID-1"]] == 120)
        #expect(bounds[["simctl", "bootstatus", "UDID-1", "-b"]] == 300)
    }
}
