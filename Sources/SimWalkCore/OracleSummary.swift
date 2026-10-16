//
// Copyright © Agulhas Labs
//

import Foundation

/// Renders an oracle check in the contract's shape: one verdict over every figure, then one line per figure per state (Brief §2.3).
///
/// **Only a figure that matched a window is a pass.** `matches none`, `not on screen`, `no figure` and `oracle failed` each qualify the verdict and are counted by name, so a clean answer means every figure the walkbook names was read, asked about and found where the oracle says it should be. **A figure on a screen the walk did not capture has a line of its own** ("screen not captured (unreachable)") and qualifies too: producing no line would pass a figure nobody checked. **So does a figure in a walkbook state a captured screen holds no capture of** ("state not captured (refused, state not applied)") — a screen whose light state matched and whose dark state was refused has not had its dark figures checked.
///
/// **A walkbook that is not the one the bundle was walked from qualifies rather than refuses.** Adding `figures` to a walkbook after a walk is the normal way to start using the oracle, so a differing hash is stated and the figures are matched by screen id.
public struct OracleSummary {
    private let bundle: CaptureBundle
    private let walkbook: Walkbook
    private let checks: [FigureCheck]
    private let walkbookChanged: Bool

    public init(_ checks: [FigureCheck], of bundle: CaptureBundle, against walkbook: Walkbook) throws {
        self.bundle = bundle
        self.walkbook = walkbook
        self.checks = checks
        walkbookChanged = try !WalkbookIdentity.isPlan(walkbook, of: bundle.manifest)
    }

    public func answer() -> Answer {
        let uncaptured = uncapturedLines
        let uncapturedStates = uncapturedStateLines
        return Answer(
            header: CaptureBundleHeader.line(of: bundle),
            verdict: verdict(uncaptured: uncaptured.count, uncapturedStates: uncapturedStates.count),
            residue: checks.map(\.rendered) + uncapturedStates + uncaptured,
            weighing: ContextSaving.weighing(bundle)
        )
    }

    /// The whole answer as text.
    public func render() -> String {
        answer().text
    }

    private func verdict(uncaptured: Int, uncapturedStates: Int) -> AnswerVerdict {
        var counts = (matched: 0, none: 0, notOnScreen: 0, unreadable: 0, failed: 0)
        for check in checks {
            switch check.outcome {
            case .matches: counts.matched += 1
            case .matchesNone: counts.none += 1
            case .notOnScreen: counts.notOnScreen += 1
            case .unreadable: counts.unreadable += 1
            case .oracleFailed: counts.failed += 1
            }
        }
        let qualifications = [
            walkbookChanged ? "walkbook changed since the walk; figures matched by screen id" : nil,
            AnswerVerdict.qualification(counts.none, "figure", "matches no window"),
            AnswerVerdict.qualification(counts.notOnScreen, "figure", "not on screen"),
            AnswerVerdict.qualification(counts.unreadable, "figure", "with no readable number"),
            AnswerVerdict.qualification(counts.failed, "figure", "the oracle failed on"),
            AnswerVerdict.qualification(uncapturedStates, "figure", "in a state that was not captured"),
            AnswerVerdict.qualification(uncaptured, "figure", "on a screen that was not captured"),
            checks.isEmpty && uncaptured + uncapturedStates == 0 ? "the walkbook names no figure on a screen the bundle holds, so nothing was checked" : nil,
        ].compactMap(\.self)
        return AnswerVerdict.reporting(qualifications: qualifications, detail: "\(counts.matched) of \(checks.count + uncapturedStates + uncaptured) figure checks matched")
    }

    /// One line per figure per walkbook state that a screen with captures holds no capture of — refused by the walk, or not in the bundle at all.
    ///
    /// Matched by slug, a state's only identity on disk. A screen with no captures at all is `uncapturedLines`' instead, one line per figure rather than one per state.
    private var uncapturedStateLines: [String] {
        let held = Dictionary(bundle.manifest.screens.map { ($0.id, $0) }) { first, _ in first }
        return walkbook.screens.flatMap { screen -> [String] in
            guard let record = held[screen.id], !record.captures.isEmpty else { return [] }
            let captured = Set(record.captures.map(\.state.slug))
            let refused = Set((record.refusedStates ?? []).map(\.slug))
            return screen.states.filter { !captured.contains($0.slug) }.flatMap { state in
                let why = refused.contains(state.slug) ? "refused, state not applied" : "not in the bundle"
                return (screen.figures ?? []).map { "\(screen.id)/\(state.slug) \($0.id): state not captured (\(why))" }
            }
        }
    }

    /// One line per figure of a screen the bundle holds no capture of, or does not hold at all.
    private var uncapturedLines: [String] {
        let held = Dictionary(bundle.manifest.screens.map { ($0.id, $0) }) { first, _ in first }
        return walkbook.screens.flatMap { screen -> [String] in
            let figures = screen.figures ?? []
            let why: String
            if let record = held[screen.id] {
                guard record.captures.isEmpty else { return [] }
                why = record.outcome.isCaptured ? "no state was captured" : CaptureBundleSummary.outcomeWords(record.outcome)
            } else {
                why = "not in the bundle"
            }
            return figures.map { "\(screen.id) \($0.id): screen not captured (\(why))" }
        }
    }
}
