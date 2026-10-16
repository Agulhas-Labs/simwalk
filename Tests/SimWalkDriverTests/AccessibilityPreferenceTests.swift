//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkDriver
import Testing

/// Every XCUITest session ends with `testmanagerd` switching the simulator's accessibility off, and the next in-process accessibility suite on that device then reads empty trees on code nothing touched — 666 of 667 failures in one app run, four times over (SimWalk#5).
///
/// What a unit suite can hold is the mechanism the live measurement settled: which key is written, through which `defaults`, that the write waits for the teardown instead of racing it, and that a write is only called a restore once it has held. That the mechanism works is a property of the simulator, established against a live device with an in-process probe and recorded in `AccessibilityPreference` and the Brief.
struct AccessibilityPreferenceTests {
    /// The measured fact the four earlier restorations missed: a hosted SwiftUI view builds its elements when `AccessibilityEnabled` is on — `ApplicationAccessibilityEnabled` alone leaves the tree empty whatever it reads.
    @Test
    func therestoreSwitchesOnTheKeyThatDecidesWhetherSwiftUIBuildsElements() {
        let device = DeviceScript(reads: ["0", "1"])

        let restoration = device.restore()

        #expect(device.writes == [
            ["simctl", "spawn", "UDID-1", "defaults", "write", "com.apple.Accessibility", "AccessibilityEnabled", "-bool", "true"],
            ["simctl", "spawn", "UDID-1", "defaults", "write", "com.apple.Accessibility", "ApplicationAccessibilityEnabled", "-bool", "true"],
        ])
        #expect(restoration.state == .restored)
        #expect(restoration.qualification == nil)
    }

    /// `simctl spawn` runs an absolute path from the host: `/usr/bin/defaults` is macOS's own, which cannot see the simulator's domain and answered "does not exist" to every read the first attempt made (SimWalk#8).
    ///
    /// Every command goes through the runtime's `defaults`.
    @Test
    func nocommandIsSpelledWithTheHostsDefaults() {
        let device = DeviceScript(reads: ["0", "1"])

        _ = device.restore()

        #expect(!device.vectors.isEmpty)
        #expect(device.vectors.allSatisfy { $0.count > 3 && $0[3] == "defaults" })
        #expect(!AccessibilityPreference.command(udid: "UDID-1").contains("/usr/bin/defaults"))
    }

    /// The teardown writes once, when the test process's connection drops; a write that landed first would be undone by it.
    ///
    /// So nothing is written until the key has been seen off — the teardown having happened — however many reads that takes.
    @Test
    func therestoreWaitsForTheTeardownBeforeWriting() {
        let device = DeviceScript(reads: ["1", "1", "0", "1"])

        let restoration = device.restore()

        #expect(device.vectors.prefix(3).allSatisfy { $0.contains("read") })
        #expect(device.vectors[3].contains("write"))
        #expect(restoration.state == .restored)
    }

    /// The review's case: a teardown landing *after* the write.
    ///
    /// Written, read back on, then off again a moment later — the restore sees it at the confirmation read, writes again, and only calls it restored once it has held.
    @Test
    func awriteALateTeardownUndoesIsWrittenAgainAndOnlyThenCalledRestored() {
        let device = DeviceScript(reads: ["0", "0", "1"])

        let restoration = device.restore()

        #expect(device.writes.count == 4)
        #expect(restoration.state == .restored)
    }

    /// A value that keeps being switched off is not written forever and is not reported as restored: the budget runs out and the answer says so, with the command.
    @Test
    func awriteThatKeepsBeingUndoneFailsWithinItsBudget() {
        let device = DeviceScript(reads: ["0"])

        let restoration = device.restore()

        #expect(restoration.state == .failed(reason: "com.apple.Accessibility AccessibilityEnabled was switched back off after 4 writes"))
        #expect(restoration.note.contains(AccessibilityPreference.command(udid: "UDID-1")))
        #expect(restoration.qualification == "device accessibility left off")
    }

    /// A teardown never seen is not a reason to leave the device off — the write still happens — but the answer says it may yet be undone, hands over the command, and qualifies the verdict.
    @Test
    func ateardownNeverSeenStillWritesAndSaysItMayBeUndone() {
        let device = DeviceScript(reads: ["1"])

        let restoration = device.restore()

        #expect(device.writes.count == 2)
        #expect(restoration.state == .restoredWithoutTeardown)
        #expect(restoration.note.contains(AccessibilityPreference.command(udid: "UDID-1")))
        #expect(restoration.qualification != nil)
    }

    /// The wait is bounded by the clock, not by a count of reads: on a runtime whose teardown never shows and whose every `simctl spawn` takes a second, forty reads was forty seconds on every walk.
    @Test
    func thewaitForTheTeardownIsBoundedByTheClockNotByACountOfReads() {
        let device = DeviceScript(reads: ["1"], spawnCost: 1)

        _ = device.restore()

        let teardownReads = device.vectors.prefix { $0.contains("read") }.count

        #expect(teardownReads <= 11)
        #expect(device.elapsed < 20)
    }

    /// A read that fails while waiting is no evidence the teardown happened, so the restore keeps waiting rather than writing early — and says afterwards that it never saw the teardown.
    @Test
    func apollThatCannotReadIsNotTakenForTheTeardown() {
        let device = DeviceScript(reads: ["1"], failingReads: 3)

        let restoration = device.restore()

        #expect(restoration.state == .restoredWithoutTeardown)
    }

    /// A write that fails is reported as the failure it is, with the command, and nothing after it is attempted.
    @Test
    func awriteThatFailsIsReportedWithTheCommand() {
        let device = DeviceScript(reads: ["0"], failWrites: true)

        let restoration = device.restore()

        #expect(restoration.state == .failed(reason: "writing com.apple.Accessibility AccessibilityEnabled did not succeed"))
        #expect(device.writes.count == 1)
        #expect(restoration.note.contains("empty trees"))
    }

    /// A write that cannot be read back is not known to be off, so it is not reported as off: "not confirmed on", with the command, on the verdict.
    @Test
    func awriteThatCannotBeReadBackIsUnconfirmedRatherThanOff() {
        let device = DeviceScript(reads: ["0"], failReadsAfterWrite: true)

        let restoration = device.restore()

        #expect(restoration.state == .unconfirmed(reason: "com.apple.Accessibility AccessibilityEnabled could not be read back"))
        #expect(restoration.qualification == "device accessibility not confirmed on")
        #expect(!restoration.note.contains("reads empty trees until"))
        #expect(restoration.note.contains(AccessibilityPreference.command(udid: "UDID-1")))
    }

    /// A confirmation read cut short at the drain limit could not be read back, so the write is unconfirmed — not "switched back off after every write" (SimWalk#30).
    @Test
    func awriteWhoseReadBackWasCutShortIsUnconfirmedRatherThanUndone() {
        let device = DeviceScript(reads: ["0"], truncateReadsAfterWrite: true)

        let restoration = device.restore()

        #expect(restoration.state == .unconfirmed(reason: "com.apple.Accessibility AccessibilityEnabled could not be read back"))
    }

    /// A write that fails where the key was never seen off leaves it unknown, not off.
    @Test
    func awriteThatFailsBeforeTheTeardownWasSeenIsUnconfirmed() {
        let device = DeviceScript(reads: ["1"], failWrites: true)

        let restoration = device.restore()

        #expect(restoration.qualification == "device accessibility not confirmed on")
    }

    /// A rewrite that fails after a confirmation read `0` is known off, not unknown (SimWalk#19): the key was just read off and could not be switched back on.
    ///
    /// Written once, read back off — a late teardown — and the second write of the deciding key fails.
    @Test
    func arewriteThatFailsAfterAConfirmationReadOffIsKnownOff() {
        let device = DeviceScript(reads: ["0", "0"], failWritesFrom: 2)

        let restoration = device.restore()

        #expect(restoration.state == .failed(reason: "writing com.apple.Accessibility AccessibilityEnabled did not succeed"))
        #expect(restoration.qualification == "device accessibility left off")
    }

    /// A failure writing the second key comes after the deciding key was written and before it was read back, so the device is not known to be off (SimWalk#19).
    ///
    /// Reported as left off, it named the wrong state of the one key that decides whether a hosted view builds elements — the key this walk had just switched on.
    @Test
    func asecondKeyThatWillNotWriteLeavesTheDecidingKeyUnconfirmedRatherThanOff() {
        let device = DeviceScript(reads: ["0"], failWritesFrom: 1)

        let restoration = device.restore()

        #expect(restoration.state == .unconfirmed(reason: "writing com.apple.Accessibility ApplicationAccessibilityEnabled did not succeed"))
        #expect(restoration.qualification == "device accessibility not confirmed on")
    }

    /// It names the device it is about, because a walk resolves whichever simulator it was pointed at and a command naming another one restores nothing.
    @Test
    func thecommandNamesTheDeviceTheWalkActuallyRan() {
        #expect(AccessibilityPreference.command(udid: "A-1") != AccessibilityPreference.command(udid: "B-2"))
        #expect(!AccessibilityPreference.command(udid: "A-1").contains("B-2"))
    }
}

extension AccessibilityPreferenceTests {
    /// Stands in for a simulator's `defaults` and the clock: reads answer from a script, in order, repeating the last answer once it runs out; every spawn and every pause moves the clock.
    final class DeviceScript {
        private(set) var vectors: [[String]] = []
        private(set) var elapsed: TimeInterval = 0
        private var reads: [String]
        private var failingReads: Int
        /// The index of the first write that fails, counting every key's write from zero; `nil` when none do.
        private let firstFailingWrite: Int?
        private let failReadsAfterWrite: Bool
        private let truncateReadsAfterWrite: Bool
        private let spawnCost: TimeInterval

        init(
            reads: [String],
            failingReads: Int = 0,
            failWrites: Bool = false,
            failWritesFrom: Int? = nil,
            failReadsAfterWrite: Bool = false,
            truncateReadsAfterWrite: Bool = false,
            spawnCost: TimeInterval = 0.2
        ) {
            self.reads = reads
            self.failingReads = failingReads
            firstFailingWrite = failWrites ? 0 : failWritesFrom
            self.failReadsAfterWrite = failReadsAfterWrite
            self.truncateReadsAfterWrite = truncateReadsAfterWrite
            self.spawnCost = spawnCost
        }

        var writes: [[String]] {
            vectors.filter { $0.contains("write") }
        }

        func restore() -> AccessibilityPreference.Restoration {
            AccessibilityPreference.restore(udid: "UDID-1", run: run, pause: pause, now: now)
        }

        var run: (String, [String]) throws -> Shell.Result {
            { [self] _, arguments in
                vectors.append(arguments)
                elapsed += spawnCost
                guard arguments.contains("read") else {
                    let fails = firstFailingWrite.map { writes.count > $0 } ?? false
                    return Shell.Result(status: fails ? 1 : 0, standardOutput: "", standardError: "")
                }
                if failingReads > 0 || (failReadsAfterWrite && !writes.isEmpty) {
                    failingReads = max(0, failingReads - 1)
                    return Shell.Result(status: 1, standardOutput: "", standardError: "does not exist")
                }
                if truncateReadsAfterWrite, !writes.isEmpty {
                    return Shell.Result(status: 0, standardOutput: "", standardError: "", truncated: true)
                }
                let answer = reads.count > 1 ? reads.removeFirst() : reads[0]
                return Shell.Result(status: 0, standardOutput: "\(answer)\n", standardError: "")
            }
        }

        var pause: (TimeInterval) -> Void {
            { [self] seconds in elapsed += seconds }
        }

        var now: () -> Date {
            { [self] in Date(timeIntervalSince1970: elapsed) }
        }
    }
}
