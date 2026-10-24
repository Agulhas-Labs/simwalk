//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SimWalkCLI
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// What `lease acquire` says about the holder it chose, against a scratch store.
struct LeaseAcquireHolderTests {
    /// A holder that may exit with the command qualifies the answer, and the warning names `--holder-pid`.
    @Test
    func aHolderThatMayExitWithTheCommandQualifiesTheAnswer() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let shell = Shell { _, arguments, _ in
            let output = arguments.starts(with: ["simctl", "list"]) ? #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[{"udid":"SHUT-1","name":"iPhone 17","state":"Shutdown"}]}}"# : ""
            return Shell.Result(status: 0, standardOutput: output, standardError: "")
        }
        let command = try LeaseAcquireCommand.parse([])
        let warning = try #require(HolderProcess.unverifiedHolderWarning(holder: 500, parent: 500, name: "make"))

        let answer = try command.answer(leasing: DeviceLeasing(store: store, shell: shell), holderPID: 500, now: Date(), holderWarning: warning)

        #expect(answer.text.contains("may exit with it and free the lease at once — pass --holder-pid <pid> naming the session's long-lived process"))
        #expect(answer.text.contains("udid: SHUT-1"))
    }

    /// SimWalk#166: `--family` chooses among unnamed devices, so it is refused beside a named one.
    @Test
    func familyIsRefusedBesideANamedDevice() throws {
        #expect(throws: (any Error).self) { try LeaseAcquireCommand.parse(["--family", "ipad", "--device", "x"]) }
        #expect(throws: (any Error).self) { try LeaseAcquireCommand.parse(["--family", "ipad", "--clone-from", "x"]) }
        #expect(throws: (any Error).self) { try LeaseAcquireCommand.parse(["--family", "ipad", "--physical", "x"]) }
        #expect(throws: (any Error).self) { try LeaseAcquireCommand.parse(["--family", "tablet"]) }
        #expect(try LeaseAcquireCommand.parse(["--family", "ipad"]).family == .ipad)
    }
}
