//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// What a walk puts back on the device when the XCUITest session is over: its accessibility, and its appearance.
///
/// One value for both, because a walk's answer reports them together — the lines under the summary, and the qualifications on the verdict when either could not be put back — and because both have to happen whether the runner succeeded or not.
public struct DeviceHandback: Equatable, Sendable {
    public let accessibility: AccessibilityPreference.Restoration
    public let appearance: DeviceAppearance.Handback
    /// Whether the runner's reset to the found appearance, after its last state, held.
    ///
    /// The state check keeps a light capture partly on the strength of the runner's resets, so a walk whose last reset did not hold says so on its verdict rather than leaving a reader to trust a keep it cannot support.
    ///
    /// **It sees the last reset and only the last one** (SimWalk#19). The runner resets before every state, and a reset in the middle of the walk can fail while the last one holds — so `.held` is evidence the resets held, never proof that none failed.
    public let reset: ResetCheck

    public init(accessibility: AccessibilityPreference.Restoration, appearance: DeviceAppearance.Handback, reset: ResetCheck = .notChecked) {
        self.accessibility = accessibility
        self.appearance = appearance
        self.reset = reset
    }

    /// Restores both on `udid`: accessibility switched back on, appearance put back to what the walk `found` — nothing to put back when it was not read.
    ///
    /// `runnerFinished` is whether the runner is known to have run its last reset — in use, whether a finalised bundle *this walk wrote* was read back, since the runner resets before it writes the manifest; the walk refuses a non-empty output path before it starts, and a manifest that started before the runner launched, so a bundle read back cannot be a previous walk's. Not `xcodebuild`'s exit status: it is non-zero for any recorded XCTest failure on a runner that ran to the end (the SimWalk#19 review). A runner that did not finish may have stopped before its last reset, so a device reading other than it was found then says nothing about the resets — only that the walk ended where its last state left it.
    ///
    /// `stoppedAt` is when the runner stopped, for a handback made after it — `session end` on a runner that had already exited — and is passed on to ``AccessibilityPreference/restore(udid:stoppedAt:run:pause:now:)``, whose teardown wait runs from it; a walk, whose runner has just stopped, passes nothing. `recorded` is an accessibility restore already made for this runner's stop — `session list`'s, recorded in the session's directory — which is reported instead of restoring again; the appearance is still put back, since `list` hands back accessibility alone.
    public static func perform(
        udid: String,
        found: Walkbook.Theme?,
        runnerFinished: Bool = true,
        stoppedAt: Date? = nil,
        recorded: AccessibilityPreference.Restoration? = nil,
        run: (String, [String]) throws -> Shell.Result,
        pause: (TimeInterval) -> Void,
        now: () -> Date
    ) -> DeviceHandback {
        // Read first, before anything here touches the appearance: the runner reset the device to what the
        // walk found after its last state, and this is the one place that can see whether that last reset held.
        let reset = resetCheck(udid: udid, found: found, runnerFinished: runnerFinished, run: run)
        let accessibility = recorded ?? AccessibilityPreference.restore(udid: udid, stoppedAt: stoppedAt, run: run, pause: pause, now: now)
        let appearance = found.map { DeviceAppearance.restore($0, udid: udid, run: run) } ?? .unknown
        return DeviceHandback(accessibility: accessibility, appearance: appearance, reset: reset)
    }

    /// Whether the runner's last reset to `found` held, read from the device before anything else touches its appearance.
    ///
    /// Its own function because a walk that settles the device between two passes (SimWalk#26) has two runners' last resets to judge, and the first one's has to be read before the settle changes the appearance — afterwards the device's appearance is the settle's doing, not the runner's.
    ///
    /// **A read cut short, or one that failed outright (a non-zero exit or a thrown error, a timeout included), is no answer, so it is `unknown`, never `didNotHold`** (SimWalk#30, SimWalk#32). A bounded `simctl` whose helper still held the pipe at the drain limit returns what was read by then, and a call that did not run to a reported answer read nothing at all — judged either way as `didNotHold`, a reset that held, or one nothing was learned about, reads as one that did not: a false statement about the device, made on a passing walk.
    ///
    /// **A cut-short or failed read after a runner that did not finish is `inconclusive`, not `unknown`** — a failed runner already qualifies the walk, and `unknown` would add a second qualification for a read a crash, not this reset, left unconfirmed.
    public static func resetCheck(udid: String, found: Walkbook.Theme?, runnerFinished: Bool, run: (String, [String]) throws -> Shell.Result) -> ResetCheck {
        found.map { found in
            guard case let .reported(read) = DeviceAppearance.reading(udid: udid, run: run) else {
                return runnerFinished ? .unknown : .inconclusive(read: nil)
            }
            guard read != found else { return .held }
            return runnerFinished ? .didNotHold(read: read) : .inconclusive(read: read)
        } ?? .notChecked
    }

    /// This handback with its reset judgement replaced — for a walk whose runners' resets were judged elsewhere, as a two-pass walk's are.
    public func replacingReset(_ reset: ResetCheck) -> DeviceHandback {
        DeviceHandback(accessibility: accessibility, appearance: appearance, reset: reset)
    }

    /// The lines printed under a walk's answer — the accessibility line always, the appearance line when it was not simply put back.
    public var notes: [String] {
        notes(by: "this walk")
    }

    /// The same lines, naming what handed the device back — `this session` at `session end`.
    public func notes(by actor: String) -> [String] {
        [accessibility.note(by: actor)] + [appearance.note(udid: accessibility.udid), resetNote].compactMap(\.self)
    }

    /// What these qualify the walk's answer by: anything that leaves the device other than the next suite needs, or other than it was found, and a reset the state check relied on that did not hold.
    public var qualifications: [String] {
        [accessibility.qualification, appearance.qualification, reset.qualification].compactMap(\.self)
    }

    /// The line saying the runner's last reset did not hold, that a failed runner left nothing to judge it by, or that the device's answer was cut short; `nil` when it held or was not checked.
    private var resetNote: String? {
        switch reset {
        case .held, .notChecked:
            return nil
        case .unknown:
            return "appearance: after the runner reset \(accessibility.udid) to the appearance it was found in, reading the device back gave no answer — the call failed outright, or its answer was still held open when the call's bound ran out — so whether the resets held is unknown, and a light state kept beside a refused dark one rests on resets nothing confirmed"
        case let .didNotHold(found):
            let read = found.map { "read \($0.rawValue)" } ?? "could not be read"
            return "appearance: after the runner reset \(accessibility.udid) to the appearance it was found in, the device \(read) — so the per-state resets may not have held either, and a light state kept beside a refused dark one may be a dark render"
        case let .inconclusive(found):
            let read = found.map { "read \($0.rawValue)" } ?? "could not be read"
            return "appearance: the runner left no finished bundle, and afterwards \(accessibility.udid) \(read) rather than the appearance it was found in — the runner may have stopped before its last reset, so this says nothing either way about whether the resets held"
        }
    }
}

public extension DeviceHandback {
    /// What the host saw of the runner's last reset to the appearance the walk found.
    enum ResetCheck: Equatable, Sendable {
        /// The device read the found appearance after the runner's last reset.
        case held
        /// There was no found appearance to reset to, so nothing was checked.
        case notChecked
        /// The device read something else, or nothing; the payload is what it read.
        case didNotHold(read: Walkbook.Theme?)
        /// The device read something else, or nothing, after a runner that left no finalised bundle — which may have stopped before its last reset, so the read is evidence of nothing; the payload is what it read.
        case inconclusive(read: Walkbook.Theme?)
        /// The read gave no answer to judge the reset by — cut short at its drain limit (`DeviceAppearance.Reading.cutShort`) or failed outright (`DeviceAppearance.Reading.failed`) — not a mismatch, which would say the device answered and the answer was wrong (SimWalk#30, SimWalk#32).
        case unknown

        /// What this qualifies the walk's answer by, or `nil` when there is nothing to say.
        ///
        /// `inconclusive` adds nothing: the runner's failure already qualifies the walk, and "a reset that did not hold" would blame the reset for where a crash left the device. `unknown` does qualify it: the state check kept light captures partly on the strength of a reset nothing confirmed, and a walk that said nothing of that would be read as having confirmed it.
        public var qualification: String? {
            switch self {
            case .didNotHold:
                "an appearance reset that did not hold"
            case .unknown:
                "an appearance reset that could not be confirmed"
            case .held, .notChecked, .inconclusive:
                nil
            }
        }

        /// The judgement for a bundle holding the work of two runners, this one's and `later`'s: a reset that did not hold in either, else one nothing could confirm, else one that could not be judged, else `held`.
        ///
        /// The worse of the two, because the bundle keeps light captures from both passes, and a keep that rested on a reset that failed in either is one a reader has to be told about. `unknown` comes before `inconclusive` because only it qualifies the walk: a runner's failure already speaks for the one, and nothing else speaks for the other.
        public func combined(with later: ResetCheck) -> ResetCheck {
            for candidate in [self, later] {
                if case .didNotHold = candidate {
                    return candidate
                }
            }
            if self == .unknown || later == .unknown {
                return .unknown
            }
            for candidate in [self, later] {
                if case .inconclusive = candidate {
                    return candidate
                }
            }
            return self == .held || later == .held ? .held : .notChecked
        }
    }
}
