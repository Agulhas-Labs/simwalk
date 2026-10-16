//
// Copyright © Agulhas Labs
//

import Foundation

/// The honest-contract verdict for one screen of a walk (Brief §3): what the runner can claim about it, stated as a type rather than left to convention.
///
/// The refusal cases exist so failure is never mistaken for validation — an unreachable screen names the route it tried instead of producing an empty capture, and a build mismatch names both hashes instead of silently validating a stale binary.
public enum ScreenOutcome: Codable, Equatable, Sendable {
    /// The screen was reached and every requested state captured.
    case captured
    /// The screen could not be reached; the payload is the route the runner **attempted**, including the step that failed — which is what makes UNREACHABLE nameable, where `ScreenRecord.routeTaken` records only the steps it completed.
    ///
    /// `reason` says why the last step did not land, where the runner knows: what its label matched, and what the tap did (SimWalk#17). An UNREACHABLE that named only the route read exactly like a missing element when the label was there and taken by a navigation bar. `nil` in a bundle written before the runner said.
    ///
    /// `cause` names a reason the walk's verdict counts on its own (`UnreachableCause`), `nil` for every other.
    ///
    /// `state` is the state whose route failed, the states that reached the screen before it, and the states never tried (SimWalk#120); a route runs once per state, so without it a reader assumes every state failed. `nil` in a bundle written before SimWalk#120.
    case unreachable(routeTried: [Walkbook.RouteStep], reason: String? = nil, cause: UnreachableCause? = nil, state: UnreachableState? = nil)
    /// The installed app's build hash does not match the build the walk claims to validate; the capture is refused.
    case buildMismatch(expected: String, found: String)
    /// The screen **was** reached, and an artefact could not be recorded; the payload names why.
    ///
    /// Distinct from `unreachable` deliberately, and the distinction is the whole point of having it: "I could not get there" is a finding about the app, where "I got there and could not write the file" is a finding about the tool, the disk, or the device. Collapsing them files a full disk as an app defect and sends someone to read a route that was walked perfectly well. The first runner did exactly that before this case existed.
    ///
    /// A screen may carry the states it *did* record alongside this — the bundle states what it holds, and a partial capture is a partial capture rather than nothing.
    case captureFailed(reason: String)
    /// The screen was reached and some of its states cannot have applied, so those states are refused rather than filed under a label the device discarded.
    ///
    /// **A refusal costs the states it names, not the screen (SimWalk#15).** `ScreenRecord.refusedStates` lists the refused ones and `captures` still holds every state the evidence does not implicate — a dark state the device ignored takes nothing from the light one beside it. Where the evidence cannot say which state is honest — two renders byte-identical across an axis nothing can measure, or a light render too dim to be told from a dark one — every state it touches is refused, because filing one of them would be a guess wearing a verdict's clothes. `StateApplicationCheck` names the states and the measurement in `reason` so an author can go and look.
    ///
    /// Never a passing outcome, even when most of the screen was filed: the bundle does not hold what the walkbook asked for here, and a reader deciding what to do next needs to know that. A record from before format 4 carries no `refusedStates` and no captures, which is the whole-screen refusal that build made.
    case stateNotApplied(reason: String)
    /// The screen was reached and captured — but at least one capture is not known by the identifier the walkbook `expect`ed: none of its screen-level identifiers is it (`found` names the first), or it has none (never anything in the tab bar, toolbar or navigation bar, the bar's title included; `ScreenIdentifierRule`).
    ///
    /// One level up from `ScreenIdentity`: that catches a step that never left the screen it was taken on; this catches a route that left, arrived, settled, and simply arrived somewhere else — the still-open "leaves the app" hole (Brief, 2026-08-17), narrowed to the half a manifest can actually check without seeing what a screenshot depicts: a wrong screen inside the same app, named by the identifier the app sets on it. `found` names each mismatched capture's own screen identifier, `nil` for one carrying none.
    ///
    /// Distinct from `stateNotApplied` on purpose: that refusal is about a state axis the device discarded, which is a finding about the device. This is a finding about the route — every state may have applied cleanly and the screen still be the wrong one. Every capture is still filed (`ExpectedScreenCheck` never shrinks what is written), because a picture of the wrong screen is exactly the evidence a reader needs to diagnose it — but it is never a passing outcome, since a bundle holding the wrong screen under a screen's id does not hold that screen.
    ///
    /// `reason` leads with the hint `ExpectedScreenCheck` adds when `expect` matched only the screen's navigation-bar title — naming the content's real identifier when it carries one, or advising an author to set one when it does not — then whatever else held at the same time: a state `StateApplicationCheck` found could not have applied (round 2), a failure that stopped the screen part-way (round 3), a write that failed — none of which stops being true because the screen was also the wrong one. `nil` when nothing held at all, the ordinary case; mirrors `unreachable`'s own optional `reason` for the same kind of "something else to say" payload.
    case unexpectedScreen(expected: String, found: [String?], reason: String? = nil)

    /// **Forward-compatible on `cause` (SimWalk#58 item 3).**
    ///
    /// A future binary's cause is a raw string this one does not name as an `UnreachableCause` case; decoding it by that raw string and matching it with the failable `init(rawValue:)` turns an unknown one into `nil` instead of failing the whole manifest to decode — the direction #55 item 2 asked for but never implemented. The rest of the enum is decoded by hand only because `cause` needed this one exception, and like the synthesized decoding it replaced it refuses a payload naming any number of cases but one (SimWalk#61 item 3): two case keys are a corrupt payload, not a choice for the first one to settle.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "ScreenOutcome payload names \(container.allKeys.count) cases, not one")
            throw DecodingError.dataCorrupted(context)
        }
        switch key {
        case .captured:
            self = .captured
        case .unreachable:
            let nested = try container.nestedContainer(keyedBy: UnreachableKeys.self, forKey: .unreachable)
            let cause = try nested.decodeIfPresent(String.self, forKey: .cause).flatMap { UnreachableCause(rawValue: $0) }
            self = try .unreachable(routeTried: nested.decode([Walkbook.RouteStep].self, forKey: .routeTried), reason: nested.decodeIfPresent(String.self, forKey: .reason), cause: cause, state: nested.decodeIfPresent(UnreachableState.self, forKey: .state))
        case .buildMismatch:
            let nested = try container.nestedContainer(keyedBy: BuildMismatchKeys.self, forKey: .buildMismatch)
            self = try .buildMismatch(expected: nested.decode(String.self, forKey: .expected), found: nested.decode(String.self, forKey: .found))
        case .captureFailed:
            let nested = try container.nestedContainer(keyedBy: ReasonKeys.self, forKey: .captureFailed)
            self = try .captureFailed(reason: nested.decode(String.self, forKey: .reason))
        case .stateNotApplied:
            let nested = try container.nestedContainer(keyedBy: ReasonKeys.self, forKey: .stateNotApplied)
            self = try .stateNotApplied(reason: nested.decode(String.self, forKey: .reason))
        case .unexpectedScreen:
            let nested = try container.nestedContainer(keyedBy: UnexpectedScreenKeys.self, forKey: .unexpectedScreen)
            self = try .unexpectedScreen(
                expected: nested.decode(String.self, forKey: .expected),
                found: nested.decode([String?].self, forKey: .found),
                reason: nested.decodeIfPresent(String.self, forKey: .reason)
            )
        }
    }

    /// Whether the bundle holds what the walkbook asked for on this screen.
    ///
    /// Exhaustive rather than `if case .captured`, so a sixth outcome is a compile error here instead of quietly counting as a success — which is the direction the mistake would go, every outcome added after `captured` having been a way of not capturing.
    public var isCaptured: Bool {
        switch self {
        case .captured: true
        case .unreachable, .buildMismatch, .captureFailed, .stateNotApplied, .unexpectedScreen: false
        }
    }

    /// The outcome to record when writing what `self` licensed then fails — the runner's one write-failure decision, made here so `swift test` can hold it (`.agents/CodingGuidelines.md`: "a decision the runner makes belongs in the core").
    ///
    /// `stateNotApplied`, `unexpectedScreen` and `captureFailed` each already carry an explanation; the write failure is folded into it rather than discarding it, which is what a write failure used to do regardless of what was about to be recorded — losing a screen mismatch's `expected`/`found`, a state refusal's own reason, or the failure that stopped a screen part-way (round 3), the moment the disk was also the problem. `captured` has nothing to fold into, so it becomes `captureFailed`: the disk, not the app, is what actually happened. `unreachable` and `buildMismatch` file nothing and carry no account of anything being filed, so they become `captureFailed` the same way.
    public func foldingWriteFailure(_ failure: String) -> ScreenOutcome {
        switch self {
        case let .stateNotApplied(reason):
            .stateNotApplied(reason: "\(reason). The states it kept could not be filed either: \(failure)")
        // No "either" here: `reason` may be nothing more than the navigation-bar-title hint, which is not
        // itself a thing that failed to be filed, so appending "either" would claim a second failure that
        // never happened (finding 4, round 5).
        case let .unexpectedScreen(expected, found, reason):
            .unexpectedScreen(expected: expected, found: found, reason: reason.map { "\($0). The states it kept could not be filed: \(failure)" } ?? "The states it kept could not be filed: \(failure)")
        case let .captureFailed(reason):
            .captureFailed(reason: "\(reason). The states it did take could not be filed either: \(failure)")
        case .captured, .unreachable, .buildMismatch:
            .captureFailed(reason: failure)
        }
    }
}

public extension ScreenOutcome {
    /// Why a screen was unreachable, where that is a fact about the walk's reads rather than the app, so the verdict names it apart from a missing control (SimWalk#48, #55 item 2).
    enum UnreachableCause: String, Codable, Equatable, Sendable {
        /// A `systemTap`'s control was live, enabled and hittable, and the app's snapshot did not hold it: a remote sheet the snapshot cannot see (`SystemSheetScope.PassedOver.unseenByTree`), cleared by terminating the sheet's host process.
        case snapshotBlind
    }

    /// Which state of a screen its route failed in (SimWalk#120).
    ///
    /// A route runs once per state and the walk stops at the first failure, so the bare route reads as though every state failed; this says which one did, what had already worked, and what was never tried.
    struct UnreachableState: Codable, Equatable, Sendable {
        public var failed: String
        public var reached: [String]
        public var notTried: [String]

        public init(failed: String, reached: [String], notTried: [String]) {
            self.failed = failed
            self.reached = reached
            self.notTried = notTried
        }

        /// The state `slug` failed in, among the screen's states in walkbook order: those before its first occurrence reached the screen, those after it were never tried.
        public init(failing slug: String, among slugs: [String]) {
            let index = slugs.firstIndex(of: slug) ?? slugs.endIndex
            self.init(failed: slug, reached: Array(slugs[..<index]), notTried: Array(slugs.dropFirst(index + 1)))
        }

        /// `in state 'X' (reached in a, b; not tried: c)`, each part only when it has something to say.
        public var clause: String {
            var parts: [String] = []
            if !reached.isEmpty {
                parts.append("reached in \(reached.joined(separator: ", "))")
            }
            if !notTried.isEmpty {
                parts.append("not tried: \(notTried.joined(separator: ", "))")
            }
            return parts.isEmpty ? "in state '\(failed)'" : "in state '\(failed)' (\(parts.joined(separator: "; ")))"
        }
    }
}

private extension ScreenOutcome {
    enum CodingKeys: String, CodingKey {
        case captured, unreachable, buildMismatch, captureFailed, stateNotApplied, unexpectedScreen
    }

    enum UnreachableKeys: String, CodingKey {
        case routeTried, reason, cause, state
    }

    enum BuildMismatchKeys: String, CodingKey {
        case expected, found
    }

    enum ReasonKeys: String, CodingKey {
        case reason
    }

    enum UnexpectedScreenKeys: String, CodingKey {
        case expected, found, reason
    }
}
