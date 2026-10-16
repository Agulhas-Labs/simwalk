//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// `simwalk device check`: what it answers for a phone that can be walked.
struct DeviceCheckCommandTests {
    /// The passcode prompt is the one thing a passing check cannot rule out: the phone may ask for it when the walk starts, so the answer says so (SimWalk#124).
    @Test(arguments: [
        [DeviceWalkCommandTests.udid, "--team", "TEAM"],
        ["--udid", DeviceWalkCommandTests.udid, "--team", "TEAM"],
    ])
    func aWalkablePhoneIsAnsweredWithTheLineAboutThePasscodePrompt(arguments: [String]) throws {
        let keep = try TemporaryDirectory()
        let phone = DeviceWalkCommandTests().phone(appearances: [DeviceWalkCommandTests.appearance("light")], keep: keep)
        let command = try DeviceCheckCommand.parse(arguments)

        let answer = try command.answer(shell: phone.shell)

        #expect(answer.verdict == .unqualified("walkable"))
        #expect(answer.residue.last == "a walk may stop on a prompt on the device asking for its passcode to allow UI automation: keep it unlocked and answer the prompt when the walk starts (SimWalk#124)")
    }

    /// The UDID is passed once, in one of its two forms: neither and both are refused at parse (SimWalk#129).
    @Test(arguments: [
        ["--team", "TEAM"],
        [DeviceWalkCommandTests.udid, "--udid", DeviceWalkCommandTests.udid],
    ])
    func aMissingOrDoubledUDIDIsRefused(arguments: [String]) {
        #expect(throws: (any Error).self) { try DeviceCheckCommand.parse(arguments) }
    }
}
