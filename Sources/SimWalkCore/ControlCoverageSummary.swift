//
// Copyright © Agulhas Labs
//

import Foundation

/// Renders a `ControlCoverage` verdict in the contract's shape: the bundle it read, then per screen the steps a walkbook would have to add.
///
/// Counts and step names only — never a tree. Each uncovered control is printed as the step that would reach it, spelled as a route shows one (`tab 'Workouts'`, `tap 'Filter'`), so the answer is the line an author copies rather than an element they then have to go and find.
public struct ControlCoverageSummary {
    private let findings: ControlCoverage.Findings
    private let bundle: CaptureBundle

    public init(_ findings: ControlCoverage.Findings, of bundle: CaptureBundle) {
        self.findings = findings
        self.bundle = bundle
    }

    /// The answer, ready for a face to print or a log to price.
    public func answer() -> Answer {
        Answer(
            header: CaptureBundleHeader.line(of: bundle),
            verdict: verdict(),
            residue: residue(),
            weighing: ContextSaving.weighing(bundle)
        )
    }

    /// The whole answer as text.
    public func render() -> String {
        answer().text
    }

    /// Uncovered controls first, then what keeps the verdict from speaking for the whole walk.
    private func verdict() -> AnswerVerdict {
        let screens = screensInOrder().count
        let stated = [
            AnswerVerdict.qualification(findings.uncovered.count, "control", "no route step covers, on \(screens) screen\(screens == 1 ? "" : "s")"),
            AnswerVerdict.qualification(findings.screensNotRead.count, "screen", "holding no captures at all"),
            AnswerVerdict.qualification(findings.screensWrongScreen.count, "screen", "that captured a different screen than the walkbook expected"),
        ].compactMap(\.self)
        let total = findings.screensRead.count + findings.screensNotRead.count + findings.screensWrongScreen.count
        let controls = "\(findings.controls) control\(findings.controls == 1 ? "" : "s")"
        return AnswerVerdict.reporting(
            qualifications: stated,
            detail: "read \(findings.screensRead.count) of \(total) screen\(total == 1 ? "" : "s"), \(controls) reachable"
        )
    }

    /// The screens the verdict could not read, then each screen's uncovered controls as the steps that would reach them.
    private func residue() -> [String] {
        var lines: [String] = []
        if !findings.screensNotRead.isEmpty {
            lines.append("not read, no captures: \(findings.screensNotRead.joined(separator: ", "))")
        }
        if !findings.screensWrongScreen.isEmpty {
            lines.append("not read, captured a different screen: \(findings.screensWrongScreen.joined(separator: ", "))")
        }
        for (screen, controls) in screensInOrder() {
            lines.append("\(screen): \(controls.count) uncovered control\(controls.count == 1 ? "" : "s")")
            lines += controls.map { "  \($0.step)" }
        }
        return lines
    }

    /// The uncovered controls grouped by the screen each was first seen on, in walk order.
    private func screensInOrder() -> [(String, [ControlCoverage.Uncovered])] {
        var order: [String] = []
        var grouped: [String: [ControlCoverage.Uncovered]] = [:]
        for control in findings.uncovered {
            if grouped[control.screenID] == nil {
                order.append(control.screenID)
            }
            grouped[control.screenID, default: []].append(control)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }
}
