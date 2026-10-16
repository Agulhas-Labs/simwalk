//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// The simulator preference an in-process accessibility suite depends on, which every XCUITest session switches off as it ends — and which a walk now switches back on (SimWalk#5).
///
/// **A walk that leaves the device worse than it found it is a walk that breaks the next suite.** SwiftUI builds no `accessibilityElements` for a hosted view while the preference is off, so the consuming project's in-process accessibility tests all fail at once, for a reason that looks exactly like a code defect on code the capture never touched: 666 of 667 failures in one real app's package run, four times over, and more than one session spent misdiagnosing it.
///
/// ## What actually switches it off, measured on 2026-09-10
///
/// **Not SimWalk, and not the key the issue was filed under.** `testmanagerd` tears down every XCUITest session when the test process's connection drops, and the teardown calls `_AXSSetAutomationEnabled(0)`, which calls `_AXSApplicationAccessibilitySetEnabled(0)` and stores *both* `AccessibilityEnabled` and `ApplicationAccessibilityEnabled` as off (the device log says so, backtrace and all, within milliseconds of `xcodebuild` returning). It is one write per session, not a stream of them. **The key that decides whether a hosted SwiftUI view builds elements is `AccessibilityEnabled`**: an in-process probe on iOS 26.5 read an empty tree with `ApplicationAccessibilityEnabled = 1, AccessibilityEnabled = 0` and a full one with the two the other way round. That is why the flag this file used to name "reads `1` even in the bad state" — it was never the one doing the damage.
///
/// **The session switches it on before it switches it off**, which is what lets a read of `0` after the runner returns stand for "the teardown has landed": sampled through the device's own `defaults` across a whole walk begun with the key at `0`, it read `0`, then `1` from the moment the session started, then `0` at the teardown, then `1` once this restore had run.
///
/// ## Why the four earlier restorations failed, and why this one does not
///
/// The 2026-08-26 round tried to read the preference and put it back, four ways, and every one failed. Two measured facts explain all four: they restored `ApplicationAccessibilityEnabled`, which leaves the tree empty whatever it reads, and they spelled the tool `/usr/bin/defaults` — and **`simctl spawn` runs an absolute path from the host, not the runtime**, so that was macOS's own `defaults` looking for a domain the simulator keeps in its own `cfprefsd`. "The domain/default pair does not exist" from a Swift `Process` and `1` from a shell was never a `Process` quirk (SimWalk#8): the shell had typed `defaults`, which `simctl spawn` resolves inside the runtime root. Both answers reproduce from a plain shell by changing only the path.
///
/// So the restore reads and writes through the runtime's `defaults`, waits — on a clock, not a count — until the teardown's write has landed, switches both keys back on, and **confirms the write held a few seconds later**, writing again if a late teardown undid it. Seeing `0` is strong evidence the teardown has happened but not proof, and the confirmation is what stands between "wrote it and read it back" and a report of success that a teardown then contradicts.
public struct AccessibilityPreference {
    /// The preference domain the simulator keeps it in.
    public static var domain: String {
        "com.apple.Accessibility"
    }

    /// The key SwiftUI consults before it builds accessibility elements for a hosted view, measured rather than assumed.
    public static var key: String {
        "AccessibilityEnabled"
    }

    /// Every key the session teardown switches off, in the order a restore puts them back — the deciding one first.
    ///
    /// `ApplicationAccessibilityEnabled` is restored as well although the probe does not need it, because the teardown turned it off in the same call and a restore that put back half of what was taken would be leaving the device other than it found it.
    public static var keys: [String] {
        [key, "ApplicationAccessibilityEnabled"]
    }

    /// Switches the preference back on for a device an XCUITest session has just finished on, and says what it did.
    ///
    /// - Parameters:
    ///   - udid: the device the walk ran on.
    ///   - stoppedAt: when the session whose teardown this waits for stopped, when that was before this call — `session list`'s case. The teardown budget runs from then, not from now, and a key that already reads on once the budget has passed was put back by something else after a teardown that landed long ago: nothing is written, and the answer is `.alreadyOn`. A walk, whose teardown has just happened, passes nothing.
    ///   - run: spawns a child and returns what it said — `Shell().run` in use, a script in a test.
    ///   - pause: waits, between two reads of the teardown and before confirming a write.
    ///   - now: the clock both waits are bounded by, so a runtime whose teardown never shows costs the budget rather than however many spawns fit in it.
    public static func restore(
        udid: String,
        stoppedAt: Date? = nil,
        run: (String, [String]) throws -> Shell.Result,
        pause: (TimeInterval) -> Void,
        now: () -> Date
    ) -> Restoration {
        let started = now()
        let teardown = waitForTeardown(udid: udid, until: min(stoppedAt ?? started, started).addingTimeInterval(teardownBudget), run: run, pause: pause, now: now)
        if teardown == .alreadyHandedBack {
            return Restoration(udid: udid, state: .alreadyOn)
        }
        let teardownSeen = teardown == .seen
        let deadline = now().addingTimeInterval(confirmationBudget)
        // What the deciding key last read before the next write: off once the teardown was seen, and off again
        // whenever a confirmation read `0` — the two reads that make "left off" a known state rather than a guess.
        var lastReadOff = teardownSeen
        var writes = 0
        while true {
            for key in keys {
                guard let written = try? run(xcrun, enableArguments(udid: udid, key: key)), written.succeeded else {
                    // Known off only when the key that failed is the deciding one and it last read off. A failure on
                    // a later key comes after the deciding key was written and never read back, so that is unknown
                    // (SimWalk#19) — as is a deciding key nobody has seen off.
                    let reason = "writing \(domain) \(key) did not succeed"
                    let knownOff = key == Self.key && lastReadOff
                    return Restoration(udid: udid, state: knownOff ? .failed(reason: reason) : .unconfirmed(reason: reason))
                }
            }
            writes += 1
            pause(confirmationDelay)
            guard let held = read(udid: udid, run: run) else {
                return Restoration(udid: udid, state: .unconfirmed(reason: "\(domain) \(key) could not be read back"))
            }
            if held == onValue {
                return Restoration(udid: udid, state: teardownSeen ? .restored : .restoredWithoutTeardown)
            }
            lastReadOff = held == offValue
            // Written, and off again a moment later: a teardown landed after the write. Write again, for as
            // long as the budget lasts — a teardown is one write per session, so this ends quickly or not at all.
            guard now() < deadline else {
                return Restoration(udid: udid, state: .failed(reason: "\(domain) \(key) was switched back off after \(writes) write\(writes == 1 ? "" : "s")"))
            }
        }
    }

    /// The `simctl` argument vectors that switch the preference back on for a device, one per key.
    ///
    /// **`defaults`, never `/usr/bin/defaults`**: `simctl spawn` runs an absolute path from the host, so the absolute spelling writes nowhere the simulator reads.
    public static func enableArguments(udid: String) -> [[String]] {
        keys.map { enableArguments(udid: udid, key: $0) }
    }

    /// The `simctl` argument vector that reads the deciding key through the runtime's own `cfprefsd`.
    public static func readArguments(udid: String) -> [String] {
        ["simctl", "spawn", udid, runtimeDefaults, "read", domain, key]
    }

    /// The commands a person runs to do what a restore does, for the case where the restore could not.
    ///
    /// Generated from `enableArguments`, so the instruction cannot drift from what the tool itself would have run.
    public static func command(udid: String) -> String {
        enableArguments(udid: udid).map { "xcrun \($0.joined(separator: " "))" }.joined(separator: " && ")
    }

    /// Reads until the teardown's `0` shows or `deadline` has passed, answering whether it showed — or, when the deadline had already passed at the first read and that read was on, that the key was handed back before this call.
    ///
    /// A read that fails is not a `0` — it is no evidence either way — so it keeps waiting like any other.
    private static func waitForTeardown(
        udid: String,
        until deadline: Date,
        run: (String, [String]) throws -> Shell.Result,
        pause: (TimeInterval) -> Void,
        now: () -> Date
    ) -> Teardown {
        let pastBudget = now() >= deadline
        var first = true
        while true {
            let value = read(udid: udid, run: run)
            if value == offValue {
                return .seen
            }
            if first, pastBudget, value == onValue {
                return .alreadyHandedBack
            }
            first = false
            guard now() < deadline else { return .notSeen }
            pause(pollInterval)
        }
    }

    private static func enableArguments(udid: String, key: String) -> [String] {
        ["simctl", "spawn", udid, runtimeDefaults, "write", domain, key, "-bool", "true"]
    }

    /// The deciding key's value as the device's own `defaults` reports it, or `nil` when it could not be read.
    ///
    /// **An answer cut short at a bounded call's drain limit could not be read either** (SimWalk#30). Taken as a value, the partial text is neither on nor off, so a confirmation read of it looked like a teardown undoing the write, and a restore that wrote the key and could not see the answer reported it switched back off after every write it made.
    private static func read(udid: String, run: (String, [String]) throws -> Shell.Result) -> String? {
        guard let result = try? run(xcrun, readArguments(udid: udid)), result.succeeded, !result.truncated else { return nil }
        return result.standardOutput.trimmed
    }

    /// The runtime's `defaults`, resolved inside the simulator's root because it is not an absolute path.
    private static var runtimeDefaults: String {
        "defaults"
    }

    private static var xcrun: String {
        "/usr/bin/xcrun"
    }

    /// What the preference reads when on — the state an in-process accessibility suite needs.
    private static var onValue: String {
        "1"
    }

    /// What it reads once the session teardown has switched it off.
    private static var offValue: String {
        "0"
    }

    /// How long the restore gives the teardown to show before writing anyway, in seconds of wall clock.
    ///
    /// Measured landing within milliseconds of `xcodebuild` returning, so the first read almost always sees it; the budget is for a runner that outlives its `xcodebuild`. A clock rather than a count of reads, because each read is a `simctl spawn` whose cost varies — forty of them was twenty-odd seconds on a runtime where the key never flips, paid on every walk.
    private static var teardownBudget: TimeInterval {
        10
    }

    private static var pollInterval: TimeInterval {
        0.25
    }

    /// How long after a write the restore reads again to see that it held.
    private static var confirmationDelay: TimeInterval {
        2.5
    }

    /// How long the restore keeps writing back a value a late teardown keeps undoing before it says so.
    private static var confirmationBudget: TimeInterval {
        10
    }
}

public extension AccessibilityPreference {
    /// What a restore did, and the one line a walk prints about it.
    struct Restoration: Codable, Equatable, Sendable {
        public let udid: String
        public let state: State

        public init(udid: String, state: State) {
            self.udid = udid
            self.state = state
        }

        /// The line printed under a walk's answer.
        ///
        /// Every walk prints one, because every walk ends a session that switched the preference off, and a reader who has met an empty-tree suite once needs to know which of these it was.
        public var note: String {
            note(by: "this walk")
        }

        /// The same line, naming what switched the preference back on: `this walk`, or `this session` at `session end`.
        public func note(by actor: String) -> String {
            let subject = "\(AccessibilityPreference.domain) \(AccessibilityPreference.key)"
            return switch state {
            case .restored:
                "accessibility: the XCUITest session switched \(subject) off as it ended, and \(actor) switched it back on for \(udid) and saw it hold — in-process accessibility suites on this device build their trees as before"
            case .alreadyOn:
                "accessibility: \(subject) already read on for \(udid), long after the XCUITest session that could switch it off had stopped — nothing to hand back"
            case .restoredWithoutTeardown:
                "accessibility: \(actor) switched \(subject) back on for \(udid) and saw it hold, but never saw the XCUITest session's teardown switch it off — if a later teardown did, an in-process accessibility suite reads empty trees until you run: \(AccessibilityPreference.command(udid: udid))"
            case let .failed(reason):
                "accessibility: the XCUITest session switched \(subject) off as it ended, and \(actor) could not switch it back on (\(reason)) — an in-process accessibility suite on this device reads empty trees until you run: \(AccessibilityPreference.command(udid: udid))"
            case let .unconfirmed(reason):
                "accessibility: \(actor) could not confirm \(subject) back on for \(udid) (\(reason)) — if an in-process accessibility suite on this device reads empty trees, run: \(AccessibilityPreference.command(udid: udid))"
            }
        }

        /// What this qualifies the walk's answer by, or `nil` when the restore is known to have held.
        ///
        /// On the verdict line rather than only in the notes, because the verdict is what an agent reads first and a device left unable to run the next suite is exactly the thing it has to act on.
        public var qualification: String? {
            switch state {
            case .restored, .alreadyOn:
                nil
            case .restoredWithoutTeardown:
                "a device accessibility restore a later teardown may undo"
            case .failed:
                "device accessibility left off"
            case .unconfirmed:
                "device accessibility not confirmed on"
            }
        }
    }
}

public extension AccessibilityPreference.Restoration {
    /// The five things a restore can have done.
    enum State: Codable, Equatable, Sendable {
        /// The teardown was seen to switch the preference off, and it was switched back on and still read on a few seconds later.
        case restored
        /// Switched on and seen to hold, but the teardown never showed within the budget — so it may yet land and undo the write.
        case restoredWithoutTeardown
        /// Found on, and nothing written, once the teardown's budget had passed since the session stopped: the teardown landed long before, and something else — a walk's handback, another session's `end`, a person — had already switched it back on.
        case alreadyOn
        /// Known off: the deciding key last read off and could not be switched back on — a write that kept being switched off, or a write of the deciding key that failed after it was read off; the payload says which.
        case failed(reason: String)
        /// Not known either way: the write could not be read back, failed where the key had not been seen off, or failed on a later key after the deciding one was written and before it was read back; the payload says which.
        case unconfirmed(reason: String)
    }
}

extension AccessibilityPreference {
    /// What the wait for the teardown found.
    enum Teardown {
        /// The key read off: the teardown landed.
        case seen
        /// The budget ran out with the key never read off.
        case notSeen
        /// The budget had run out before the first read, which read on: put back after a teardown that landed long ago.
        case alreadyHandedBack
    }
}
