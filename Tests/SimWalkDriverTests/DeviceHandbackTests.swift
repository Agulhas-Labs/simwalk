//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkDriver
import Testing

/// A walk hands the device back as it found it: its appearance put back, its accessibility switched back on, and anything it could not put back on the verdict line.
///
/// The runner sets the appearance per state and never used to reset it, so a walk ending on a dark state left the simulator dark for the next walk — whose state check then had a dark device under a failed light/dark comparison and no way to know.
struct DeviceHandbackTests {
    /// `simctl ui <udid> appearance` is how the host knows the device's appearance, and an answer it does not recognise is not guessed at.
    @Test
    func theappearanceIsReadFromSimctlAndAnUnknownAnswerIsNotGuessed() throws {
        #expect(try DeviceAppearance.read(udid: "UDID-1", run: Self.answering(appearance: "dark")) == .dark)
        #expect(try DeviceAppearance.read(udid: "UDID-1", run: Self.answering(appearance: "light")) == .light)
        #expect(try DeviceAppearance.read(udid: "UDID-1", run: Self.answering(appearance: "unsupported")) == nil)
        #expect(DeviceAppearance.readArguments(udid: "UDID-1") == ["simctl", "ui", "UDID-1", "appearance"])
    }

    /// SimWalk#136: a read stalled behind `xcodebuild -runFirstLaunch` is thrown with its cause, where a plain timeout stays a read that failed (SimWalk#32).
    @Test
    func aReadStalledOnFirstLaunchIsThrownAndAPlainTimeoutIsAFailedRead() throws {
        let stall = ShellError.stalledOnFirstLaunch(command: "xcrun simctl ui UDID-1 appearance", seconds: 10)
        let timeout = ShellError.timedOut(command: "xcrun simctl ui UDID-1 appearance", seconds: 10)

        let thrown = #expect(throws: ShellError.self) {
            try DeviceAppearance.reading(udid: "UDID-1") { _, _ in throw stall }
        }

        #expect(thrown == stall)
        #expect(try DeviceAppearance.reading(udid: "UDID-1") { _, _ in throw timeout } == .failed)
        #expect(try DeviceAppearance.read(udid: "UDID-1") { _, _ in throw timeout } == nil)
    }

    /// The appearance the walk found is the one it puts back — set, then read back as that.
    @Test
    func thefoundAppearanceIsPutBackAndReadBack() {
        var device = "dark"
        var vectors: [[String]] = []
        let run: (String, [String]) throws -> Shell.Result = { _, arguments in
            vectors.append(arguments)
            if arguments.count == 5 {
                device = arguments[4]
            }
            return Shell.Result(status: 0, standardOutput: "\(device)\n", standardError: "")
        }

        let handback = DeviceAppearance.restore(.light, udid: "UDID-1", run: run)

        #expect(vectors.first == ["simctl", "ui", "UDID-1", "appearance", "light"])
        #expect(device == "light")
        #expect(handback == .restored(.light))
    }

    /// A put-back that does not read back is a failure, and it qualifies the answer with the command that finishes the job.
    @Test
    func anappearanceThatDoesNotReadBackIsAQualifiedFailure() {
        let handback = DeviceAppearance.restore(.light, udid: "UDID-1", run: Self.answering(appearance: "dark"))

        #expect(handback == .failed(found: .light, reason: "it did not read back as light"))
        #expect(handback.qualification == "a device appearance that could not be put back")
        #expect(handback.note(udid: "UDID-1", by: "this walk")?.contains("xcrun simctl ui UDID-1 appearance light") == true)
    }

    /// SimWalk#159: every caller that hands the appearance back names itself in the line, so an `inspect` or a session is never called a walk.
    @Test(arguments: ["this walk", "this session", "this inspect"])
    func theAppearanceLinesNameWhatHandedTheDeviceBack(actor: String) {
        let unknown = DeviceAppearance.Handback.unknown.note(udid: "UDID-1", by: actor)
        let failed = DeviceAppearance.Handback.failed(found: .light, reason: "boom").note(udid: "UDID-1", by: actor)
        let unconfirmed = DeviceAppearance.Handback.unconfirmed(found: .light, reason: "cut short").note(udid: "UDID-1", by: actor)
        let left = DeviceAppearance.Handback.leftToAnotherHolder(found: .light).note(udid: "UDID-1", by: actor)

        #expect(unknown?.contains("before \(actor) started, so \(actor) could not put it back") == true)
        #expect(failed?.contains("was light before \(actor) started and could not be put back (boom)") == true)
        #expect(unconfirmed?.contains("was light before \(actor) started and \(actor) could not confirm it was put back (cut short)") == true)
        #expect(left?.contains("was light before \(actor) started, and another holder took it") == true)
        for line in [unknown, failed, unconfirmed, left].compactMap(\.self) {
            #expect(actor == "this walk" || !line.contains("walk"))
            #expect(actor == "this session" || !line.contains("session"))
        }
    }

    /// SimWalk#159: the appearance's actor follows `appearanceBy` when given — `session end` puts the appearance back itself even where accessibility's restore was `session list`'s.
    @Test
    func theAppearanceLineFollowsAppearanceByWhenGiven() {
        let handback = DeviceHandback(
            accessibility: AccessibilityPreference.Restoration(udid: "UDID-1", state: .restored),
            appearance: .failed(found: .light, reason: "boom")
        )

        let split = handback.notes(by: "`session list`", appearanceBy: "this session")
        let same = handback.notes(by: "this inspect")

        #expect(split.first?.contains("`session list` switched it back on") == true)
        #expect(split.contains { $0.hasPrefix("appearance:") && $0.contains("before this session started") })
        #expect(same.contains { $0.hasPrefix("appearance:") && $0.contains("before this inspect started") })
        #expect(handback.notes.contains { $0.hasPrefix("appearance:") && $0.contains("before this walk started") })
    }

    /// SimWalk#79: `session end` hands the device back too, and its line names the session — a walk's names the walk.
    @Test
    func theAccessibilityLineNamesWhatHandedTheDeviceBack() {
        let handback = DeviceHandback(
            accessibility: AccessibilityPreference.Restoration(udid: "UDID-1", state: .restored),
            appearance: .restored(.light)
        )

        #expect(handback.notes.first?.contains("this walk switched it back on") == true)
        #expect(handback.notes(by: "this session").first?.contains("this session switched it back on") == true)
        #expect(handback.notes(by: "this session").first?.contains("this walk") == false)
    }

    /// Both halves reach the verdict: a failed accessibility restore and an appearance that was never read each qualify the walk, where a clean handback qualifies nothing.
    @Test
    func whatCouldNotBePutBackQualifiesTheWalk() {
        let clean = DeviceHandback(
            accessibility: AccessibilityPreference.Restoration(udid: "UDID-1", state: .restored),
            appearance: .restored(.light)
        )
        let broken = DeviceHandback(
            accessibility: AccessibilityPreference.Restoration(udid: "UDID-1", state: .failed(reason: "writing did not succeed")),
            appearance: .unknown
        )

        #expect(clean.qualifications.isEmpty)
        #expect(clean.notes.count == 1)
        #expect(broken.qualifications == ["device accessibility left off", "a device appearance that could not be read"])
        #expect(broken.notes.count == 2)
    }

    /// The runner resets the device to what the walk found after its last state; a device reading otherwise afterwards means the resets the state check relied on may not have held, and the verdict says so.
    @Test
    func aresetThatDidNotHoldQualifiesTheWalk() {
        let drifted = DeviceHandback.perform(udid: "UDID-1", found: .light, run: Self.answering(appearance: "dark"), pause: { _ in }, now: Self.clock())
        let held = DeviceHandback.perform(udid: "UDID-1", found: .light, run: Self.answering(appearance: "light"), pause: { _ in }, now: Self.clock())

        #expect(drifted.reset == .didNotHold(read: .dark))
        #expect(drifted.qualifications.contains("an appearance reset that did not hold"))
        #expect(drifted.notes.contains { $0.contains("may be a dark render") })
        #expect(held.reset == .held)
        #expect(!held.qualifications.contains("an appearance reset that did not hold"))
    }

    /// A runner that did not finish may have stopped before its last reset, so a device reading otherwise afterwards is no evidence about the resets (SimWalk#19).
    ///
    /// The line used to say "the per-state resets may not have held either" and qualify the walk for a reset that did not hold — blaming the resets for where a crash left the device, on a walk its runner failure already qualifies.
    @Test
    func adeviceLeftOtherwiseByAFailedRunnerSaysNothingAboutTheResets() {
        let handback = DeviceHandback.perform(
            udid: "UDID-1",
            found: .light,
            runnerFinished: false,
            run: Self.answering(appearance: "dark"),
            pause: { _ in },
            now: Self.clock()
        )

        #expect(handback.reset == .inconclusive(read: .dark))
        #expect(!handback.qualifications.contains("an appearance reset that did not hold"))
        #expect(!handback.notes.contains { $0.contains("the per-state resets may not have held") })
        #expect(handback.notes.contains { $0.contains("says nothing either way about whether the resets held") })
    }

    /// A reset read cut short at the drain limit is unknown, not a reset that did not hold (SimWalk#30): `didNotHold` says the device answered and the answer was wrong, and here it did not answer.
    ///
    /// Still a qualification — the state check kept light captures on the strength of a reset nothing confirmed — but one that says so, rather than one that blames the reset.
    @Test
    func aresetReadCutShortIsUnknownRatherThanAResetThatDidNotHold() {
        let handback = DeviceHandback.perform(udid: "UDID-1", found: .light, run: Self.cutShort, pause: { _ in }, now: Self.clock())

        #expect(handback.reset == .unknown)
        #expect(!handback.qualifications.contains("an appearance reset that did not hold"))
        #expect(handback.qualifications.contains("an appearance reset that could not be confirmed"))
        #expect(handback.notes.contains { $0.contains("was cut short") })
        #expect(!handback.notes.contains { $0.contains("may be a dark render") })
    }

    /// A put-back whose read-back was cut short is not said to have read back as something else (SimWalk#30) — and is not said to have failed either: the write held, only the confirmation is missing.
    @Test
    func aputBackWhoseReadBackWasCutShortIsUnconfirmedRatherThanFailed() {
        let handback = DeviceAppearance.restore(.light, udid: "UDID-1", run: Self.cutShort)

        #expect(handback == .unconfirmed(found: .light, reason: "it was set, but reading it back was cut short, so nothing confirms it"))
        #expect(handback.qualification == "a device appearance not confirmed put back")
    }

    /// A reset read cut short after a runner that did not finish is inconclusive, not unknown (SimWalk#30): a failed runner already qualifies the walk, and the read is no evidence about the resets either way — the runner may have stopped before its last one.
    @Test
    func aresetReadCutShortAfterAFailedRunnerIsInconclusive() {
        let handback = DeviceHandback.perform(
            udid: "UDID-1",
            found: .light,
            runnerFinished: false,
            run: Self.cutShort,
            pause: { _ in },
            now: Self.clock()
        )

        #expect(handback.reset == .inconclusive(read: nil))
        #expect(!handback.qualifications.contains("an appearance reset that could not be confirmed"))
        #expect(handback.notes.contains { $0.contains("says nothing either way about whether the resets held") })
    }

    /// A reset read that failed outright — a non-zero exit, or a thrown error such as a timeout — is unknown, not a reset that did not hold (SimWalk#32): the call gave no answer, so there is nothing for `didNotHold(read: nil)` to have compared against `found`.
    @Test
    func aresetReadThatFailedIsUnknownRatherThanAResetThatDidNotHold() {
        let handback = DeviceHandback.perform(udid: "UDID-1", found: .light, run: Self.failing, pause: { _ in }, now: Self.clock())

        #expect(handback.reset == .unknown)
        #expect(!handback.qualifications.contains("an appearance reset that did not hold"))
        #expect(handback.qualifications.contains("an appearance reset that could not be confirmed"))
        #expect(!handback.notes.contains { $0.contains("may be a dark render") })
    }

    /// A bundle holding two runners' work (SimWalk#26) is judged by the worse of their last resets, whichever came first: a reset that did not hold in either is the one a reader has to be told about.
    @Test
    func tworunnersResetsAreJudgedByTheWorseOfThem() {
        #expect(DeviceHandback.ResetCheck.held.combined(with: .didNotHold(read: .dark)) == .didNotHold(read: .dark))
        #expect(DeviceHandback.ResetCheck.didNotHold(read: nil).combined(with: .held) == .didNotHold(read: nil))
        #expect(DeviceHandback.ResetCheck.held.combined(with: .inconclusive(read: .dark)) == .inconclusive(read: .dark))
        #expect(DeviceHandback.ResetCheck.inconclusive(read: .dark).combined(with: .unknown) == .unknown)
        #expect(DeviceHandback.ResetCheck.unknown.combined(with: .didNotHold(read: .dark)) == .didNotHold(read: .dark))
        #expect(DeviceHandback.ResetCheck.held.combined(with: .held) == .held)
        #expect(DeviceHandback.ResetCheck.notChecked.combined(with: .notChecked) == .notChecked)
    }

    /// SimWalk#128: a holder that takes the device while the handback waits out the teardown budget has nothing written under it.
    ///
    /// The busy question, free when the handback began, is asked again after the wait, before each write, and each part's note says why it was left.
    @Test
    func aDeviceTakenDuringTheTeardownWaitHasNeitherWriteMade() {
        var vectors: [[String]] = []
        var elapsed: TimeInterval = 0

        let handback = DeviceHandback.perform(
            udid: "UDID-1",
            found: .light,
            runnerFinished: false,
            isDeviceBusy: { $0.timeIntervalSince1970 >= 5 },
            run: { _, arguments in
                vectors.append(arguments)
                return Shell.Result(status: 0, standardOutput: arguments.contains("appearance") ? "light\n" : "1\n", standardError: "")
            },
            pause: { elapsed += $0 },
            now: { Date(timeIntervalSince1970: elapsed) }
        )

        #expect(elapsed >= 10)
        #expect(!vectors.contains { $0.contains("write") })
        #expect(!vectors.contains(DeviceAppearance.setArguments(.light, udid: "UDID-1")))
        #expect(handback.accessibility.state == .leftToAnotherHolder)
        #expect(handback.appearance == .leftToAnotherHolder(found: .light))
        #expect(handback.notes.filter { $0.contains("another holder took") }.count == 2)
        #expect(handback.qualifications.contains("a device appearance left to another holder that took the device during the handback"))
    }

    /// A handback left to another holder says what finishes it when something will, and keeps the run-by-hand advice when nothing will.
    @Test
    func theLeftToAnotherHolderNotesNameWhatCompletesThemOnlyWhenTold() {
        let handback = DeviceHandback(
            accessibility: AccessibilityPreference.Restoration(udid: "UDID-1", state: .leftToAnotherHolder),
            appearance: .leftToAnotherHolder(found: .light)
        )

        let byHand = handback.notes(by: "this session")
        let completed = handback.notes(by: "this session", completedBy: "`simwalk session end s1`")

        #expect(byHand == handback.notes(by: "this session", completedBy: nil))
        #expect(byHand.filter { $0.contains("once it is done") && $0.contains("run: ") }.count == 2)
        #expect(completed.filter { $0.contains("run: ") }.isEmpty)
        #expect(completed.contains { $0.hasPrefix("accessibility:") && $0.hasSuffix("— `simwalk session end s1` switches it back on once that holder is done") })
        #expect(completed.contains { $0.hasPrefix("appearance:") && $0.hasSuffix("— `simwalk session end s1` puts it back once that holder is done") })
    }

    /// A session whose own lease lapsed during the handback leaves the undone parts to no holder: `omittingUndone` drops their notes and qualifications, whichever actor named them, and only theirs.
    @Test
    func omittingUndoneDropsThePartsLeftToAnotherHolderAndNothingElse() {
        let undone = DeviceHandback(
            accessibility: AccessibilityPreference.Restoration(udid: "UDID-1", state: .leftToAnotherHolder),
            appearance: .leftToAnotherHolder(found: .light)
        ).replacingReset(.unknown)
        let done = DeviceHandback(
            accessibility: AccessibilityPreference.Restoration(udid: "UDID-1", state: .restored),
            appearance: .restored(.light)
        )

        let notes = undone.notes(by: "`session list`", appearanceBy: "this session", omittingUndone: true)

        #expect(notes.count == 1)
        #expect(notes.first?.contains("reading the device back gave no answer") == true)
        #expect(undone.qualifications(omittingUndone: true) == [DeviceHandback.ResetCheck.unknown.qualification].compactMap(\.self))
        #expect(undone.qualifications(omittingUndone: false) == undone.qualifications)
        #expect(undone.qualifications.count > 1)
        #expect(done.notes(by: "this session", omittingUndone: true) == done.notes(by: "this session"))
        #expect(done.qualifications(omittingUndone: true) == done.qualifications)
    }

    /// SimWalk#128: the appearance write asks again too — a holder that takes the device after accessibility was switched back on still has its appearance left alone.
    @Test
    func aDeviceTakenAfterTheAccessibilityWriteHasNoAppearanceWrite() {
        var vectors: [[String]] = []
        var accessibility = "0"
        var asked = 0
        var elapsed: TimeInterval = 0

        let handback = DeviceHandback.perform(
            udid: "UDID-1",
            found: .dark,
            runnerFinished: false,
            isDeviceBusy: { _ in
                asked += 1
                return asked > 1
            },
            run: { _, arguments in
                vectors.append(arguments)
                if arguments.contains("write") {
                    accessibility = "1"
                }
                return Shell.Result(status: 0, standardOutput: arguments.contains("appearance") ? "dark\n" : "\(accessibility)\n", standardError: "")
            },
            pause: { elapsed += $0 },
            now: { Date(timeIntervalSince1970: elapsed) }
        )

        #expect(handback.accessibility.state == .restored)
        #expect(asked == 2)
        #expect(!vectors.contains(DeviceAppearance.setArguments(.dark, udid: "UDID-1")))
        #expect(handback.appearance == .leftToAnotherHolder(found: .dark))
    }

    /// A clock that moves a second each time it is asked, so a restore's budget runs out in a test rather than in wall time.
    private static func clock() -> () -> Date {
        var seconds: TimeInterval = 0
        return {
            seconds += 1
            return Date(timeIntervalSince1970: seconds)
        }
    }

    /// A shell whose every call succeeds with its output cut short at the drain limit — the child exited, and something it left behind held the pipe.
    private static func cutShort(_: String, _: [String]) -> Shell.Result {
        Shell.Result(status: 0, standardOutput: "", standardError: "", truncated: true)
    }

    /// A shell whose every call exits non-zero — a read that failed outright, rather than one that ran to an answer (SimWalk#32).
    private static func failing(_: String, _: [String]) -> Shell.Result {
        Shell.Result(status: 1, standardOutput: "", standardError: "An error was encountered processing the command (code=164)\n")
    }

    /// A shell that answers every `simctl ui` read with `appearance` and every write with success.
    private static func answering(appearance: String) -> (String, [String]) throws -> Shell.Result {
        { _, _ in Shell.Result(status: 0, standardOutput: "\(appearance)\n", standardError: "") }
    }
}
