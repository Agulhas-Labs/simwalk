//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// The runner's read of when the device booted (SimWalk#90 item 3), pinned here because the runner's own target cannot be run by `swift test`.
struct DeviceBootTimeTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func aValidValueGivesTheAgeAgainstNow() throws {
        let age = DeviceBootTime.age(in: [DeviceBootTime.environmentKey: "1799999930.5"], now: Self.now)

        #expect(try #require(age) == 69.5)
    }

    @Test
    func aMissingValueGivesNil() {
        #expect(DeviceBootTime.age(in: [:], now: Self.now) == nil)
        #expect(DeviceBootTime.age(in: ["SIMWALK_DEVICE_BOOTED_AT_TYPO": "1799999930"], now: Self.now) == nil)
    }

    @Test(arguments: ["", "yesterday", "12 s", "nan", "inf"])
    func aMalformedValueGivesNil(raw: String) {
        #expect(DeviceBootTime.age(in: [DeviceBootTime.environmentKey: raw], now: Self.now) == nil)
    }

    @Test
    func aFutureValueGivesNil() {
        #expect(DeviceBootTime.age(in: [DeviceBootTime.environmentKey: "1800000001"], now: Self.now) == nil)
    }

    /// The host's key is the runner's with the prefix `xcodebuild` strips; the full host-to-runner round trip is in `RunnerInvocationTests`.
    @Test
    func theHostKeyIsTheRunnerKeyWithTheForwardingPrefix() {
        #expect(DeviceBootTime.hostEnvironmentKey == "TEST_RUNNER_SIMWALK_DEVICE_BOOTED_AT")
        #expect(DeviceBootTime.environmentKey == "SIMWALK_DEVICE_BOOTED_AT")
    }
}
