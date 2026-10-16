//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkDriver
import Testing

/// SimWalk#26: the settle is the one remedy measured to work — `appearance dark`, a shutdown and a boot — and it hands the device back in the appearance the walk found it in.
struct DeviceSettleTests {
    /// A device found light is booted dark and put back to light, on the walk's own device and nothing else, in the order that cured every sighting: set dark, shut down, boot, wait for the boot, put back, read back — every step bounded.
    @Test
    func asettleBootsTheDeviceDarkAndPutsBackTheLightItWasFoundIn() {
        let device = SimulatedDevice()

        let outcome = DeviceSettle.perform(udid: "UDID-1", found: .light, run: device.run)

        #expect(outcome == .settled)
        #expect(device.vectors == [
            ["simctl", "ui", "UDID-1", "appearance", "dark"],
            ["simctl", "shutdown", "UDID-1"],
            ["simctl", "boot", "UDID-1"],
            ["simctl", "bootstatus", "UDID-1", "-b"],
            ["simctl", "ui", "UDID-1", "appearance", "light"],
            ["simctl", "ui", "UDID-1", "appearance"],
        ])
        #expect(device.appearance == "light")
        #expect(device.bounds.allSatisfy { $0 == DeviceSettle.stepTimeout })
        #expect(outcome.qualification == nil)
        #expect(outcome.note(udid: "UDID-1") == nil)
    }

    /// The review's case: a device found dark is booted dark as well — the cure, not its mirror — and nothing is switched after the boot; the appearance is only read back.
    ///
    /// Round 1 booted it light and switched it to dark afterwards, the trap's own trigger.
    @Test
    func adeviceFoundDarkIsBootedDarkAndNothingIsSwitchedAfterTheBoot() {
        let device = SimulatedDevice()

        let outcome = DeviceSettle.perform(udid: "UDID-1", found: .dark, run: device.run)

        #expect(outcome == .settled)
        #expect(device.vectors == [
            ["simctl", "ui", "UDID-1", "appearance", "dark"],
            ["simctl", "shutdown", "UDID-1"],
            ["simctl", "boot", "UDID-1"],
            ["simctl", "bootstatus", "UDID-1", "-b"],
            ["simctl", "ui", "UDID-1", "appearance"],
        ])
        #expect(device.appearance == "dark")
    }

    /// A device that will not boot again stops the settle there — nothing after it runs — and the answer says so, with the command that leaves the device usable.
    @Test
    func adeviceThatWouldNotBootStopsTheSettleAndSaysHowToBootIt() {
        let device = SimulatedDevice(failing: ["boot"])

        let outcome = DeviceSettle.perform(udid: "UDID-1", found: .light, run: device.run)

        guard case .failed(.boot, _) = outcome else {
            Issue.record("a boot that failed must stop the settle at the boot, got \(outcome)")
            return
        }

        #expect(!device.vectors.contains { $0.contains("bootstatus") })
        #expect(outcome.qualification == "an appearance settle that did not complete")
        #expect(outcome.note(udid: "UDID-1")?.contains("run: xcrun simctl boot UDID-1") == true)
    }

    /// A boot that wedges ends at its bound as the same failed settle — the step named, the command that boots the device on the answer — rather than holding the walk for as long as the device takes.
    @Test
    func abootThatOutlivesItsBoundStopsTheSettleAndSaysHowToBootIt() {
        let device = SimulatedDevice(timingOut: ["bootstatus"])

        let outcome = DeviceSettle.perform(udid: "UDID-1", found: .light, run: device.run)

        guard case let .failed(.bootStatus, reason) = outcome else {
            Issue.record("a boot that outlived its bound must stop the settle there, got \(outcome)")
            return
        }

        #expect(reason.contains("did not finish within 300s"))
        #expect(!device.vectors.contains { $0 == ["simctl", "ui", "UDID-1", "appearance", "light"] })
        #expect(outcome.qualification == "an appearance settle that did not complete")
        #expect(outcome.note(udid: "UDID-1")?.contains("run: xcrun simctl boot UDID-1") == true)
    }

    /// `simctl boot` on a device someone else booted in the meantime fails with "current state: Booted" — which is the state wanted, as `Simulator.boot` reads it too.
    @Test
    func adeviceAlreadyBootedWhenAskedToBootIsWhatWasWanted() {
        let device = SimulatedDevice(failing: ["boot"], failure: "Unable to boot device in current state: Booted")

        #expect(DeviceSettle.perform(udid: "UDID-1", found: .dark, run: device.run) == .settled)
    }

    /// A boot whose output was cut short at the drain limit cannot say whether the device was already booted, so the settle goes on to the wait, which is judged by its status (SimWalk#30).
    @Test
    func abootWhoseOutputWasCutShortIsJudgedByTheWaitAfterIt() {
        let device = SimulatedDevice(failing: ["boot"], failure: "", truncating: ["boot"])

        #expect(DeviceSettle.perform(udid: "UDID-1", found: .dark, run: device.run) == .settled)
        #expect(device.vectors.contains(["simctl", "bootstatus", "UDID-1", "-b"]))
    }

    /// A read-back cut short at the drain limit is not said to have read back as nothing (SimWalk#30).
    @Test
    func areadBackCutShortDoesNotSayTheDeviceReadNothing() {
        let device = SimulatedDevice(truncating: ["ui"])

        let outcome = DeviceSettle.perform(udid: "UDID-1", found: .dark, run: device.run)

        #expect(outcome == .failed(.readBack(.dark), reason: "reading it back was cut short, so nothing confirms it"))
    }

    /// A failed step whose output was cut short leaves `failureLine` with nothing to say — stderr and stdout both empty — so the settle says the output was cut short rather than printing an empty reason (SimWalk#32).
    @Test
    func afailedStepWhoseOutputWasCutShortSaysSoRatherThanAnEmptyReason() {
        let device = SimulatedDevice(failing: ["shutdown"], truncating: ["shutdown"])

        let outcome = DeviceSettle.perform(udid: "UDID-1", found: .dark, run: device.run)

        #expect(outcome == .failed(.shutdown, reason: "output cut short"))
    }

    /// A put-back whose read-back was cut short is not a settle: the next pass would walk on an appearance nothing confirmed (SimWalk#30).
    @Test
    func aputBackCutShortStopsTheSettleRatherThanPassingIt() {
        let device = SimulatedDevice(truncating: ["ui"])

        let outcome = DeviceSettle.perform(udid: "UDID-1", found: .light, run: device.run)

        guard case .failed(.putBack(.light), _) = outcome else {
            Issue.record("an unconfirmed put-back must stop the settle, got \(outcome)")
            return
        }
    }

    /// The round-2 review's finding 1: a device the walk was given by UDID, or one it booted itself, is the walk's to reboot — however it was named.
    @Test(arguments: [(true, "UDID-1"), (false, "UDID-1"), (false, "iPhone 17"), (false, nil)] as [(Bool, String?)])
    func adeviceGivenByUDIDOrBootedByTheWalkMayBeRebooted(bootedWhenResolved: Bool, requested: String?) {
        let simulator = Simulator(udid: "UDID-1", name: "iPhone 17", osVersion: "27.0", isBooted: bootedWhenResolved)

        #expect(DeviceSettle.mayReboot(simulator, requested: requested, leased: false))
    }

    /// And a device found booted and taken by name, or as the booted default, may be another session's — it is not rebooted.
    @Test(arguments: ["iPhone 17", nil] as [String?])
    func adeviceFoundBootedAndTakenByNameOrByDefaultMayNotBeRebooted(requested: String?) {
        let simulator = Simulator(udid: "UDID-1", name: "iPhone 17", osVersion: "27.0", isBooted: true)

        #expect(!DeviceSettle.mayReboot(simulator, requested: requested, leased: false))
    }

    /// A device walked under its lease is the walk's to reboot even though it was found booted and not named by UDID: no walk without the token could have taken it (Brief §2.4).
    @Test
    func adeviceWalkedUnderItsLeaseMayBeRebooted() {
        let simulator = Simulator(udid: "UDID-1", name: "iPhone 17", osVersion: "27.0", isBooted: true)

        #expect(DeviceSettle.mayReboot(simulator, requested: nil, leased: true))
    }

    /// The settle a walk prints for a device it will not reboot is the one it would have run — set dark, shut down, boot, wait, and the found appearance back where the boot changed it.
    @Test
    func theprintedSettleIsTheStepsASettleRuns() {
        #expect(DeviceSettle.command(udid: "UDID-1", found: .light) == "xcrun simctl ui UDID-1 appearance dark && xcrun simctl shutdown UDID-1 && xcrun simctl boot UDID-1 && xcrun simctl bootstatus UDID-1 -b && xcrun simctl ui UDID-1 appearance light")
        #expect(DeviceSettle.command(udid: "UDID-1", found: .dark) == "xcrun simctl ui UDID-1 appearance dark && xcrun simctl shutdown UDID-1 && xcrun simctl boot UDID-1 && xcrun simctl bootstatus UDID-1 -b")
    }
}

extension DeviceSettleTests {
    /// A simulator as `simctl` answers it: an appearance that `ui` sets and reads, subcommands that fail on request, and subcommands that run past whatever bound they were given.
    final class SimulatedDevice {
        private(set) var vectors: [[String]] = []
        /// The bound each command was run under, in the order they ran.
        private(set) var bounds: [TimeInterval] = []
        private(set) var appearance = "light"
        private let failing: [String]
        private let failure: String
        private let timingOut: [String]
        /// Subcommands whose output is cut short at the drain limit: the status stands, the text is empty and marked truncated.
        private let truncating: [String]

        init(failing: [String] = [], failure: String = "An error was encountered processing the command (code=164)", timingOut: [String] = [], truncating: [String] = []) {
            self.failing = failing
            self.failure = failure
            self.timingOut = timingOut
            self.truncating = truncating
        }

        var run: (String, [String], TimeInterval) throws -> Shell.Result {
            { [self] _, arguments, bound in
                vectors.append(arguments)
                bounds.append(bound)
                if arguments.count > 1, timingOut.contains(arguments[1]) {
                    throw ShellError.timedOut(command: (["xcrun"] + arguments).joined(separator: " "), seconds: bound)
                }
                let truncated = arguments.count > 1 && truncating.contains(arguments[1])
                if arguments.count > 1, failing.contains(arguments[1]) {
                    return Shell.Result(status: 1, standardOutput: "", standardError: truncated ? "" : "\(failure)\n", truncated: truncated)
                }
                guard arguments.starts(with: ["simctl", "ui"]) else {
                    return Shell.Result(status: 0, standardOutput: "", standardError: "")
                }
                if arguments.count == 5 {
                    appearance = arguments[4]
                }
                return Shell.Result(status: 0, standardOutput: truncated ? "" : "\(appearance)\n", standardError: "", truncated: truncated)
            }
        }
    }
}
