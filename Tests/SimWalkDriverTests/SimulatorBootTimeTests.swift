//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkDriver
import Testing

/// When a device booted is read from its `launchd_sim`'s line in `ps`, someone else's format, so what it is read as belongs in a test (SimWalk#88).
struct SimulatorBootTimeTests {
    private static var udid: String {
        "11111111-2222-3333-4444-000000000008"
    }

    private static var other: String {
        "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0"
    }

    /// Every form `etime` takes — `mm:ss`, `hh:mm:ss`, `dd-hh:mm:ss` — in seconds.
    @Test
    func everyElapsedTimeFormIsReadInSeconds() {
        let read = ["00:07", "04:15", "1:02:03", "2-01:02:03"].map(Simulator.elapsedSeconds(fromEtime:))

        #expect(read == [7, 255, 3723, 2 * 86400 + 3723])
    }

    /// Anything that is not an `etime` is `nil`, never a guess.
    @Test
    func anElapsedTimeThatDoesNotParseIsNil() {
        let read = ["", "12", "abc", "04:xx", "1:2:3:4", "1-02:03", "-01:00", "1--01:02:03", "04:-15"].map(Simulator.elapsedSeconds(fromEtime:))

        #expect(read.allSatisfy { $0 == nil })
    }

    /// The device's own `launchd_sim` is read, past another device's and past a process of its own that is not `launchd_sim`.
    @Test
    func onlyTheDevicesOwnLaunchdSimIsRead() {
        let listing = """
          501       00:30 launchd_sim /Users/me/Library/Developer/CoreSimulator/Devices/\(Self.other)/data/var/run/launchd_bootstrap.plist
          502       09:00 /usr/libexec/someservice /Users/me/Library/Developer/CoreSimulator/Devices/\(Self.udid)/data/x
        84326       04:15 launchd_sim /Users/me/Library/Developer/CoreSimulator/Devices/\(Self.udid)/data/var/run/launchd_bootstrap.plist
        """

        #expect(Simulator.bootUptime(of: Self.udid, inProcessList: listing) == 255)
    }

    /// No line for the device, or one whose elapsed time does not parse, is `nil`.
    @Test
    func aDeviceWithNoReadableLaunchdSimIsNil() {
        let otherOnly = "  501  00:30 launchd_sim /Users/me/Library/Developer/CoreSimulator/Devices/\(Self.other)/data/var/run/launchd_bootstrap.plist"
        let garbled = "  501  soon launchd_sim /Users/me/Library/Developer/CoreSimulator/Devices/\(Self.udid)/data/var/run/launchd_bootstrap.plist"

        #expect(Simulator.bootUptime(of: Self.udid, inProcessList: otherOnly) == nil)
        #expect(Simulator.bootUptime(of: Self.udid, inProcessList: garbled) == nil)
        #expect(Simulator.bootUptime(of: Self.udid, inProcessList: "") == nil)
    }

    /// The boot instant is `now` less the process's age; a `ps` that fails is `nil`, never a throw.
    @Test
    func theBootInstantIsNowLessTheAgeAndAFailedReadIsNil() {
        let simulator = Simulator(udid: Self.udid, name: "iPhone 17 Pro", osVersion: "27.0", isBooted: true)
        let line = "84326 01:10 launchd_sim /Users/me/Library/Developer/CoreSimulator/Devices/\(Self.udid)/data/var/run/launchd_bootstrap.plist\n"
        let listed = Shell(script: { _, _, _ in Shell.Result(status: 0, standardOutput: line, standardError: "") })
        let failed = Shell(script: { _, _, _ in Shell.Result(status: 1, standardOutput: "", standardError: "ps: no") })
        let now = Date(timeIntervalSince1970: 1_000_000)

        #expect(simulator.bootedAt(now: now, shell: listed) == Date(timeIntervalSince1970: 1_000_000 - 70))
        #expect(simulator.bootedAt(now: now, shell: failed) == nil)
    }
}
