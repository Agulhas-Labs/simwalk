//
// Copyright © Agulhas Labs
//

import Foundation

/// A ``BundleDiff`` in the contract's shape: what was compared and what the diff measures, one verdict, then the flags and everything not compared.
///
/// **Clean means nothing was left out.** A diff with no flag but a screen on one side only, a screen not compared or a tree that could not be read, or an Apple audit asked for and lost has not said the two walks agree, so each of those qualifies the verdict as a flag does — and is named in it.
///
/// The saving is both bundles' screenshots and trees: the material a reader would otherwise have opened to see the two side by side.
public struct BundleDiffSummary {
    private let diff: BundleDiff
    private let reference: CaptureBundle
    private let run: CaptureBundle
    private let crops: BundleDiffCrops?

    public init(_ diff: BundleDiff, reference: CaptureBundle, run: CaptureBundle, crops: BundleDiffCrops? = nil) {
        self.diff = diff
        self.reference = reference
        self.run = run
        self.crops = crops
    }

    public func answer() -> Answer {
        Answer(
            header: (identityLines + BundleDiffRendering.cropsLines(crops)).joined(separator: "\n"),
            verdict: AnswerVerdict.reporting(qualifications: qualifications, detail: BundleDiffRendering.comparedTally(diff) + BundleDiffRendering.inheritedClause(diff)),
            residue: BundleDiffRendering.unpairedLines(diff) + diff.screens.flatMap { BundleDiffRendering.screenLines($0, crops: crops) } + BundleDiffRendering.appleBundleLine(diff) + BundleDiffRendering.cleanLine(diff),
            weighing: weighing
        )
    }

    /// The identity lines, the first carrying the note of each bundle read through the suffix added to its path (SimWalk#107), labelled by role so a reader knows which path was completed.
    private var identityLines: [String] {
        var lines = BundleDiffRendering.identityLines(diff)
        let notes = [("run", run.pathNote), ("reference", reference.pathNote)].compactMap { role, note in note.map { "\(role) \($0)" } }
        if !notes.isEmpty, !lines.isEmpty {
            lines[0] += "  " + notes.joined(separator: "  ")
        }
        return lines
    }

    private var qualifications: [String] {
        let unreadable = diff.screens.flatMap(\.states).filter { !$0.isCompared }.count
        return [
            AnswerVerdict.qualification(diff.flagCount, "flag", "raised"),
            AnswerVerdict.qualification(diff.unpairedScreens.count, "screen", "on one side only"),
            AnswerVerdict.qualification(diff.screens.reduce(0) { $0 + $1.unpairedStates.count }, "state", "on one side only"),
            AnswerVerdict.qualification(diff.screens.filter { !$0.isCompared }.count, "screen", "not compared"),
            AnswerVerdict.qualification(unreadable, "state", "not compared for an unreadable tree"),
            appleQualification,
            AnswerVerdict.qualification(crops?.failedCount ?? 0, "crop", "not written"),
        ].compactMap(\.self)
    }

    /// `3 states' Apple audits not compared` (`1 state's …`): an audit asked for and lost must not read as a pass.
    private var appleQualification: String? {
        let count = diff.appleNotCompared.count
        return count > 0 ? "\(count) state\(count == 1 ? "'s" : "s'") Apple audits not compared" : nil
    }

    private var weighing: ContextSaving? {
        let weighed = [ContextSaving.weighing(reference), ContextSaving.weighing(run)].compactMap(\.self)
        guard !weighed.isEmpty else { return nil }
        return ContextSaving(screenshotTokens: weighed.flatMap(\.screenshotTokens), treeBytes: weighed.reduce(0) { $0 + $1.treeBytes }, servedBytes: 0)
    }
}
