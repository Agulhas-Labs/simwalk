//
// Copyright © Agulhas Labs
//

import Foundation

/// Renders a capture bundle's manifest as an answer in the contract's shape — what `simwalk bundle inspect` prints, and what a `walk` reports when the runner has had its say.
///
/// The refusals are the reason this exists as a rendering rather than a directory listing: a screen that was not reached, and a build that did not match, each print their evidence on the line that reports them. A summary that showed only counts would be the vacuous visual pass the differ was built to end (Brief §2.2), one level up.
///
/// **The shape is the shared answer contract** (Sift's answer contract, Docs/AnswerContract.md in github.com/Agulhas-Labs/sift): the header names the build, the plan, the device and how much of the bundle settled; the verdict names every qualification before the counters; the residue carries the screens and their evidence; the last line prices what the answer stood in for. Nothing that is empty is printed as a heading, so a clean walk's report is the header, the verdict, its screens and the saving.
public struct CaptureBundleSummary {
    private let bundle: CaptureBundle
    private let qualifications: [String]
    private let notes: [String]

    /// - Parameters:
    ///   - bundle: the walk's output.
    ///   - qualifiedBy: qualifications the bundle itself cannot carry, because they are facts about the *run* — a runner failure the bundle outlived is the only one today.
    ///   - notes: lines printed under the residue that qualify nothing: what the walk left the device set to, and the detail behind a stated qualification.
    public init(_ bundle: CaptureBundle, qualifiedBy qualifications: [String] = [], notes: [String] = []) {
        self.bundle = bundle
        self.qualifications = qualifications
        self.notes = notes
    }

    /// The answer, ready for a face to print or a log to price.
    ///
    /// `appending` carries residue the caller measured for itself — `inspect`'s on-disk report — which stays a fact about the answer rather than about the manifest, and rides after the manifest's own residue for that reason.
    public func answer(appending extra: [String] = []) -> Answer {
        var residue = bundle.manifest.screens.enumerated().map { Self.screenLine($0.element, position: $0.offset + 1) }
        residue.append(Self.settleLine(bundle.manifest))
        residue += Self.appleAuditLines(bundle.manifest)
        residue += Self.appearanceSettleLines(bundle.manifest)
        // What the host set on the device for the walk and put back after it — the record, so `bundle inspect` says it a week later.
        residue += bundle.manifest.deviceSetup.map { [""] + $0.lines } ?? []
        residue += Self.resetPermissionLines(bundle.manifest)
        residue += Self.unsettledLines(bundle.manifest)
        residue += Self.chromeOnlyLines(bundle.manifest)
        residue += Self.unverifiedLines(bundle.manifest)
        if !extra.isEmpty {
            residue += [""] + extra
        }
        if !notes.isEmpty {
            residue += [""] + notes
        }
        return Answer(
            header: CaptureBundleHeader.line(of: bundle),
            verdict: verdict(),
            residue: residue,
            weighing: ContextSaving.weighing(bundle)
        )
    }

    /// The whole answer as text.
    public func render() -> String {
        answer().text
    }

    /// The verdict: every qualification named, then what the walk actually holds.
    ///
    /// One pass over the screens, classifying each once, and the switch is exhaustive rather than a set of filters — so a sixth `ScreenOutcome` is a compile error here instead of a screen that silently counts towards nothing. The qualifications lead because they are the numbers that can go down (contract §2), and a count that only rises reads as success whatever the truth is; the ones that are zero are not printed at all (§3), where the old tally spelled out four zeroes on every clean walk.
    private func verdict() -> AnswerVerdict {
        let screens = bundle.manifest.screens
        var counts = (captured: 0, unreachable: 0, snapshotBlind: 0, buildMismatch: 0, captureFailed: 0, stateNotApplied: 0, unexpectedScreen: 0, captures: 0)
        for screen in screens {
            switch screen.outcome {
            case .captured:
                counts.captured += 1
            case .unreachable(_, _, .snapshotBlind, _):
                // Named apart from a missing control (SimWalk#48): the control was there, and the app's snapshot could not see it.
                counts.snapshotBlind += 1
            case .unreachable:
                counts.unreachable += 1
            case .buildMismatch:
                counts.buildMismatch += 1
            case .captureFailed:
                counts.captureFailed += 1
            case .stateNotApplied:
                counts.stateNotApplied += 1
            case .unexpectedScreen:
                counts.unexpectedScreen += 1
            }
            counts.captures += screen.captures.count
        }
        let stated = [
            AnswerVerdict.qualification(bundle.manifest.movingCaptures.count, "capture", "taken before the tree settled"),
            AnswerVerdict.qualification(bundle.manifest.chromeOnlyCaptures.count, "capture", "holding the app's chrome and nothing else"),
            AnswerVerdict.qualification(bundle.manifest.unverifiedCaptures.count, "capture", "with a state axis set and unverified"),
            AnswerVerdict.qualification(counts.unreachable, "screen", "unreachable"),
            AnswerVerdict.qualification(counts.snapshotBlind, "screen", "unreachable behind a system sheet the app's snapshot cannot see"),
            AnswerVerdict.qualification(counts.buildMismatch, "screen", "refused on a build mismatch"),
            AnswerVerdict.qualification(counts.captureFailed, "screen", "that failed mid-capture"),
            AnswerVerdict.qualification(counts.stateNotApplied, "screen", "refused, state not applied"),
            AnswerVerdict.qualification(counts.unexpectedScreen, "screen", "not the screen its walkbook expected"),
        ].compactMap(\.self) + qualifications
        return AnswerVerdict.reporting(
            qualifications: stated,
            detail: "\(counts.captured) of \(screens.count) screens captured · \(counts.captures) capture\(counts.captures == 1 ? "" : "s")"
        )
    }

    /// What settling was actually measured against, stated on every bundle rather than only when something went wrong.
    ///
    /// The threshold is half of what `axTreeSettled` means and was recorded nowhere, so "the tree had stopped" could not be read as the statement about a window that it is. It sits in the residue as the arithmetic behind the header's `settled:` figure (contract §4), and the caveat rides on the same line because it is the same fact: a quiet accessibility tree is not a still screen, and a reader who is told the first without the second will read a chart mid-draw-in as settled.
    private static func settleLine(_ manifest: CaptureManifest) -> String {
        let threshold = manifest.settleQuietMilliseconds.map { "\($0)ms" } ?? "unrecorded (this bundle predates the runner recording it)"
        return "settle: the accessibility tree had to hold still for \(threshold) before each capture — animations it cannot see (chart draw-in, cross-fades, image decode) are not covered"
    }

    /// What the walk recorded of Apple's accessibility audit, or nothing when it audited no state (E1a).
    ///
    /// Rendered from the manifest, so every answer that summarises the bundle says it a week later. The cost rides on the line because it is why the audit is opt-in: the walk took that much longer.
    static func appleAuditLines(_ manifest: CaptureManifest) -> [String] {
        let entries = manifest.appleAuditEntries
        guard !entries.isEmpty else { return [] }
        let sorted = entries.map(\.milliseconds).sorted()
        let seconds = { (milliseconds: Int) in String(format: "%.1f", Double(milliseconds) / 1000) }
        let issues = entries.reduce(0) { $0 + $1.issueCount }
        let failed = entries.filter(\.failed).count
        let states = entries.count == 1 ? "1 state" : "\(entries.count) states"
        // A call that threw has no audit cost to report, so a run where every call threw states no timings.
        if failed == entries.count {
            return ["apple audit: \(states) asked, none completed (\(failed) failed) — opt-in (appleAudit / --apple-audit)"]
        }
        let failure = failed == 0 ? "" : ", \(failed) failed"
        let issueCount = issues == 1 ? "1 issue" : "\(issues) issues"
        return ["apple audit: \(states), p50 \(seconds(sorted[(sorted.count - 1) / 2])) s, max \(seconds(sorted[sorted.count - 1])) s — opt-in (appleAudit / --apple-audit); \(issueCount) recorded\(failure)"]
    }

    /// The settle the walk made and the screens it walked again (SimWalk#26), or nothing when it made none.
    ///
    /// **Printed, not only recorded** — a field a walk writes and no reader sees is a habit, not a record. It is why the walk took longer, and why a screen above is its second attempt: each retried screen is named with what its first attempt found and what the one filed found, so "recovered by the settle" and "refused again after it" read differently. Not a qualification: a settle that held changed nothing any capture claims, and a screen still refused after it is already counted on the verdict.
    private static func appearanceSettleLines(_ manifest: CaptureManifest) -> [String] {
        guard let settle = manifest.appearanceSettle else { return [] }
        let seconds = String(format: "%.1f", Double(settle.milliseconds) / 1000)
        let count = settle.retried.count
        let cause = "\(count) screen\(count == 1 ? "" : "s") had a state refused on appearance — a render that did not show the appearance its state asked for, as a device that reports one appearance and draws the other produces"
        let header: String
        if let declined = settle.declined {
            header = "appearance settle: \(cause) — and no settle was made: \(declined.reason); \(count == 1 ? "it was" : "they were") not walked again, and the first attempt stands:"
        } else if let failure = settle.settleFailure {
            header = "appearance settle: \(cause) — so the device was to be set \(settle.appearance.rawValue), shut down and booted, and the settle stopped \(failure) after \(seconds)s; \(count == 1 ? "it was" : "they were") not walked again, and the first attempt stands:"
        } else {
            let back = settle.found == settle.appearance
                ? "shut down and booted — the appearance it was found in"
                : "shut down, booted and put back to \(settle.found.rawValue)"
            let then = settle.secondPassFailure.map { "and walking \(count == 1 ? "it" : "them") again left nothing that could be folded in (\($0)), so the first attempt stands:" }
                ?? "and \(count == 1 ? "it was" : "they were") walked again:"
            header = "appearance settle: \(cause) — so the device was set \(settle.appearance.rawValue), \(back) (\(seconds)s), \(then)"
        }
        let filed = Dictionary(manifest.screens.map { ($0.id, $0.outcome) }, uniquingKeysWith: { first, _ in first })
        let screens = settle.retried.map { retry in
            // Which refusals caused the settle, when they are not all of them — a Dynamic Type or locale collision
            // beside a refusal on appearance is refused too, and a reboot was not made for it.
            let cause = retry.firstRefusedOnAppearance == retry.firstRefusedStates
                ? ""
                : " ([\(retry.firstRefusedOnAppearance.map(\.slug).joined(separator: ", "))] on appearance)"
            let first = "    \(retry.id) — first refused [\(retry.firstRefusedStates.map(\.slug).joined(separator: ", "))]\(cause)"
            guard settle.folded else { return "\(first); its first attempt stands" }
            if let notFolded = retry.notFolded {
                return "\(first); \(notFolded)"
            }
            return "\(first); now \(filed[retry.id].map(outcomeWords) ?? "not recorded")"
        }
        // What a person runs where the walk would not, kept with the bundle rather than only in the walk's answer.
        let remedy = settle.declined.map { ["  to settle it, then walk again: \($0.command)"] } ?? []
        return ["", header] + screens + remedy
    }

    /// A verdict in the words the verdict line counts it under.
    static func outcomeWords(_ outcome: ScreenOutcome) -> String {
        switch outcome {
        case .captured: "captured"
        case .unreachable: "unreachable"
        case .buildMismatch: "refused on a build mismatch"
        case .captureFailed: "failed mid-capture"
        case .stateNotApplied: "refused, state not applied"
        case .unexpectedScreen: "not the screen its walkbook expected"
        }
    }

    /// Captures taken before the accessibility tree stopped changing, or while it still held only the app's chrome when the content wait ran out (SimWalk#81), named rather than left in the manifest.
    ///
    /// Without this the report is identical whether every capture was of a still tree or none of them were, which is the ambiguity that made a half-rendered insight card unattributable — the reviewer could not tell a capture race from an app bug, and the summary is where that has to be said. The verdict already counts them; this names which.
    private static func unsettledLines(_ manifest: CaptureManifest) -> [String] {
        let unsettled = manifest.unsettledCaptures
        guard !unsettled.isEmpty else { return [] }
        return [
            "",
            "⚠ \(unsettled.count) capture\(unsettled.count == 1 ? " was" : "s were") taken before the accessibility tree stopped changing, or while it held only the app's chrome — read them knowing that:",
        ] + unsettled.map { "    \($0.screenID) [\($0.stateSlug)]" }
    }

    /// The protected resources a walk reset before launching the app (SimWalk#62 item 2), which it does not restore.
    ///
    /// Read from the screens' `launchResets`, which the runner writes where it applies a reset and so holds for a screen that filed no capture. A bundle without the field falls back to the captures' states: a capture is the record that its state's launch happened, so that reading misses a reset whose screen filed nothing. Either way the line states only the reset — a route's `systemTap` may well have granted the permission again, and nothing here reads the device afterwards.
    private static func resetPermissionLines(_ manifest: CaptureManifest) -> [String] {
        struct Reset {
            let screen: String
            let state: String
            let resources: [String]
        }
        var resets: [Reset] = []
        for screen in manifest.screens {
            if let recorded = screen.launchResets {
                resets += recorded.map { Reset(screen: screen.id, state: $0.state, resources: $0.resources) }
            } else {
                resets += screen.captures.filter { !$0.state.resourcesToReset.isEmpty }.map {
                    Reset(screen: screen.id, state: $0.state.slug, resources: $0.state.resourcesToReset.map(\.rawValue))
                }
            }
        }
        guard !resets.isEmpty else { return [] }
        let named = Set(resets.flatMap(\.resources))
        let resources = ProtectedResourceName.allCases.map(\.rawValue).filter { named.contains($0) }
        return [
            "",
            "⚠ permissions reset before launch and not restored by the walk, for \(manifest.appBundleID): \(resources.joined(separator: ", ")) (states: \(resets.map { "\($0.screen) [\($0.state)]" }.joined(separator: ", ")))",
        ]
    }

    /// Captures that set a state axis their artefacts show nothing to verify by, each with the axes named — set, and not shown to have taken.
    private static func unverifiedLines(_ manifest: CaptureManifest) -> [String] {
        let unverified = manifest.screens.flatMap { screen in
            screen.captures.compactMap { capture in
                capture.unverifiedAxes.map { "    \(screen.id) [\(capture.state.slug)]: \($0.joined(separator: ", "))" }
            }
        }
        guard !unverified.isEmpty else { return [] }
        return [
            "",
            "⚠ \(unverified.count) capture\(unverified.count == 1 ? " sets" : "s set") a state axis its artefacts show nothing to verify by — set, not shown to have taken:",
        ] + unverified
    }

    /// Captures holding the app's chrome and nothing else, which is a screen that had not arrived.
    ///
    /// Named beside the unsettled ones because it is the same class of qualification read the same way, and because the fix is nameable: a screen whose content streams in states its own `settle` in the walkbook rather than the whole walk paying for it.
    private static func chromeOnlyLines(_ manifest: CaptureManifest) -> [String] {
        let chromeOnly = manifest.chromeOnlyCaptures
        guard !chromeOnly.isEmpty else { return [] }
        return [
            "",
            "⚠ \(chromeOnly.count) capture\(chromeOnly.count == 1 ? " holds" : "s hold") the app's chrome and nothing else — the screen stayed bare past the \(Int(SettleWindow.contentWait)) s content wait; only a `settle` above \(SettleWindow.contentWaitExtendedAboveQuiet.formatted()) s extends it, and a screen that is bare by design (a canvas or chart with no labels) always carries this warning:",
        ] + chromeOnly.map { "    \($0.screenID) [\($0.stateSlug)]" }
    }

    /// One screen's line, carrying the route it walked as well as its verdict.
    ///
    /// A captured screen's route is the answer to "how was this reached", which a bundle records and nothing surfaced; an unreachable one prints both routes, because how far it got and what it was reaching for are different facts and the gap between them is where the failure is.
    ///
    /// **`position` leads the line** — this screen's 1-based place in this listing — because it is the number `bundle screen`'s own `<step>` counts from, and after a `--screens` walk or a walkbook reorder that number is not the walkbook's own position for the screen, only this bundle's.
    static func screenLine(_ screen: CaptureManifest.ScreenRecord, position: Int) -> String {
        switch screen.outcome {
        case .captured:
            // A capture filed as identical to its base says so on the line (SimWalk#18): two states, one picture,
            // on purpose — the device was already in the conditions the second one asked for.
            let states = screen.captures.map { capture in
                capture.identicalTo.map { "\(capture.state.slug) (= \($0))" } ?? capture.state.slug
            }.joined(separator: ", ")
            return "  \(position) \(screen.id) — captured [\(states)] via \(screen.routeTaken.rendered)\(ownSettle(screen))"
        case let .unreachable(routeTried, reason, _, state):
            // Why the last step did not land, where the runner knows — what its label matched and what the tap
            // did — because "route tried" alone reads like a missing element when a navigation bar took the label.
            let why = reason.map { " — \($0)" } ?? ""
            let stateClause = state.map { " \($0.clause)" } ?? ""
            return "  \(position) \(screen.id) — UNREACHABLE\(stateClause), route tried: \(routeTried.rendered); completed: \(screen.routeTaken.rendered)\(why)"
        case let .buildMismatch(expected, found):
            return "  \(position) \(screen.id) — REFUSED, build mismatch: expected \(expected), found \(found)"
        case let .captureFailed(reason):
            // The states it *did* record are named, because "reached, got light, failed on dark" is a
            // different fact from "reached and recorded nothing", and a reader acts on them differently.
            let recorded = screen.captures.isEmpty ? "nothing" : "[\(screen.captures.map(\.state.slug).joined(separator: ", "))]"
            return "  \(position) \(screen.id) — CAPTURE FAILED after \(recorded), via \(screen.routeTaken.rendered): \(reason)"
        case let .stateNotApplied(reason):
            // Named as a refusal rather than as a shortfall, because the screen was reached and drawn:
            // what is missing is any way to say which state the picture is of.
            guard let refused = screen.refusedStates else {
                return "  \(position) \(screen.id) — REFUSED, state not applied, via \(screen.routeTaken.rendered): \(reason)"
            }
            // Both lists, because "refused dark, kept light" and "refused dark, reached nothing" are
            // different facts, and the kept states are the ones a reader can go and look at.
            let kept = screen.captures.isEmpty ? "nothing" : "[\(screen.captures.map(\.state.slug).joined(separator: ", "))]"
            return "  \(position) \(screen.id) — REFUSED [\(refused.map(\.slug).joined(separator: ", "))], state not applied; kept \(kept), via \(screen.routeTaken.rendered): \(reason)"
        case let .unexpectedScreen(expected, found, reason):
            // Captured, named, and printed — the wrong screen is evidence a reader needs to see, not a
            // shortfall to hide behind a count.
            let foundText = found.map { $0 ?? "no identifier" }.joined(separator: ", ")
            // `found` is deduplicated across every state the screen took — `ExpectedScreenCheck` runs before
            // `StateApplicationCheck` decides what to keep — so the states it summarises are named as that
            // same set: the ones filed and the ones refused, both of which were checked (round 3). Naming
            // only the filed ones pinned a refused state's identifier on a kept one. No count: after a write
            // failure the states taken are in neither list, and the reason beside this says so.
            let captured = screen.captures.isEmpty ? "nothing" : "[\(screen.captures.map(\.state.slug).joined(separator: ", "))]"
            let refused = screen.refusedStates.map { "; refused [\($0.map(\.slug).joined(separator: ", "))]" } ?? ""
            // `reason` may lead with the hint explaining the mismatch itself — `expect` naming a title, and
            // what the content's real identifier is — which is not a second finding, so this does not print
            // it as one (round 5, finding 4); whatever else held at the same time is named beside it exactly
            // as `stateNotApplied`'s own reason is printed above.
            let reasonClause = reason.map { " — \($0)" } ?? ""
            return "  \(position) \(screen.id) — REFUSED, expected '\(expected)', found [\(foundText)] among the states it took (captured \(captured)\(refused)), via \(screen.routeTaken.rendered)\(reasonClause)"
        }
    }

    /// The trailing clause naming a screen's own quiet period, or nothing when it ran at the walk's.
    ///
    /// Printed on the screen's own line rather than in the settle line above, because that line states one number for the walk and a screen that paid for more has to say so where a reader is already looking at it.
    private static func ownSettle(_ screen: CaptureManifest.ScreenRecord) -> String {
        screen.settleQuietMilliseconds.map { " · settle \($0)ms" } ?? ""
    }
}
