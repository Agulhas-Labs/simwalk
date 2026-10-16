//
// Copyright © Agulhas Labs
//

import Foundation

/// Answers `simwalk session step`: the verdict — landed, blocked, or the refusal of a step not taken — then `step: <the landed step's JSON>`, `bound: <the element a tap, scrollTo or type bound>` where it bound one, `screen <hash>` and the delta.
///
/// **A blocked step is a qualified answer, a stale guard a refusal.** A step that was taken and did not land is the tool working and the app not having what was asked for (exit 2), and its screen and delta are still worth reading; a guard that no longer matches means nothing was done, so it is thrown — `refused`, exit 1 — naming both hashes and saying to read again.
public struct LiveSessionStepQuery {
    private let sent: Walkbook.RouteStep
    private let stepAnswer: LiveSessionStepAnswer
    private let screen: LiveScreen?

    /// - Parameters:
    ///   - sent: the step as the caller wrote it, which a blocked verdict names.
    public init(sent: Walkbook.RouteStep, answer stepAnswer: LiveSessionStepAnswer, screen: LiveScreen?) {
        self.sent = sent
        self.stepAnswer = stepAnswer
        self.screen = screen
    }

    /// The answer, or the refusal of a step not taken.
    public func answer() throws -> Answer {
        if stepAnswer.outcome == .snapshotChanged {
            throw LiveSessionError.snapshotChanged(expected: stepAnswer.expectedHash ?? "", found: stepAnswer.foundHash ?? "")
        }
        guard let screen, let tree = screen.tree else {
            throw LiveScreenError.appNotRunning(bundleID: screen?.appBundleID ?? "the app", udid: screen?.device.udid ?? "the device")
        }
        var residue: [String] = []
        let verdict: AnswerVerdict
        let still = AnswerVerdict.qualification(screen.settled == false ? 1 : 0, "read after the step", "taken while the tree was still changing")
        switch stepAnswer.outcome {
        case .landed:
            let landed = stepAnswer.landed ?? sent
            residue.append("step: \(Self.json(landed.asWritten))")
            if let bound = stepAnswer.bound {
                residue.append("bound: \(BundleScreenQuery.line(bound))")
            }
            verdict = .reporting(qualifications: [still].compactMap(\.self), detail: "landed \(landed) — now on root \(BundleScreenQuery.rootClause(tree))")
        case .blocked, .snapshotChanged:
            let reason = stepAnswer.reason.map { " — \($0)" } ?? ""
            verdict = .qualified(["blocked: \(sent) did not land\(reason)"] + [still].compactMap(\.self), detail: "nothing added to the route — on root \(BundleScreenQuery.rootClause(tree))")
        }
        residue.append("screen \(ScreenHash.of(tree))")
        residue += stepAnswer.delta?.residue ?? []
        return Answer(header: LiveScreenQuery.header(of: screen), verdict: verdict, residue: residue)
    }

    /// `step` as a walkbook writes it, on one line.
    static func json(_ step: Walkbook.RouteStep) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(step)).flatMap { String(data: $0, encoding: .utf8) } ?? step.description
    }
}
