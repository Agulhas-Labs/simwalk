//
// Copyright © Agulhas Labs
//

import Foundation

/// Renders a `BundleLabels` report in the contract's shape: the bundle it read, one verdict, then per claim the parts that have something in them.
public struct BundleLabelsSummary {
    private let report: BundleLabels.Report
    private let bundle: CaptureBundle

    public init(_ report: BundleLabels.Report, of bundle: CaptureBundle) {
        self.report = report
        self.bundle = bundle
    }

    public func answer() -> Answer {
        Answer(header: CaptureBundleHeader.line(of: bundle), verdict: verdict(), residue: residue(), weighing: ContextSaving.weighing(bundle))
    }

    /// The whole answer as text.
    public func render() -> String {
        answer().text
    }

    /// Failing and missing items qualify the verdict; a manual line never does, since it is not something the bundle could have supplied.
    private func verdict() -> AnswerVerdict {
        let claims = report.claims
        let stated = [
            AnswerVerdict.qualification(claims.map(\.findingCount).reduce(0, +), "finding", "failing a claim"),
            AnswerVerdict.qualification(claims.map(\.missing.count).reduce(0, +), "item", "missing"),
        ].compactMap(\.self)
        let count = { (status: BundleLabels.ClaimReport.Status) in claims.filter { $0.status == status }.count }
        let screens = "\(report.screenCount) screen\(report.screenCount == 1 ? "" : "s")"
        return AnswerVerdict.reporting(
            qualifications: stated,
            detail: "\(claims.count) claim\(claims.count == 1 ? "" : "s") over \(screens): \(count(.holds)) hold, \(count(.fails)) fail, \(count(.incomplete)) incomplete, \(count(.manualOnly)) manual only"
        )
    }

    private func residue() -> [String] {
        report.claims.flatMap { claim in
            var lines = ["[\(claim.claim.rawValue)] \(claim.status.rawValue)"]
            for (name, items) in [("evidence", claim.evidence), ("fails", claim.fails), ("missing", claim.missing), ("manual", claim.manual)] where !items.isEmpty {
                lines.append("  \(name) (\(items.count)):")
                lines += items.map { "    \($0)" }
            }
            return lines
        }
    }
}
