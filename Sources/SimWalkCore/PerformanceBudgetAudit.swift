//
// Copyright © Agulhas Labs
//

import Foundation

/// The `performanceBudget` rule of `bundle audit` (SimWalk#67, M4): holds each screen the walkbook gives a performance budget (`launchMs`, `transitionHitches`, `cpuMs`, `memoryPeakMB`) to the figures a device walk measured, each against the **median** of the recorded measurements.
///
/// **Built as `MotionBudgetAudit` is, and with its rule: a budget is never "within budget" without a figure.** A screen that was not captured, a capture with no `performance` record, a record lacking the metric a budget needs, a metric in a unit this rule does not read, and **every capture of a simulator bundle** are each UNREACHABLE, naming the screen, the state and the route the walk took, and qualify the verdict as a finding does. A simulator's figures are not a device's, so none are ever recorded there and none are read.
///
/// **Units are converted on reading, and nowhere in the record** (``PerformanceFigure``), so the manifest keeps what XCTest said.
struct PerformanceBudgetAudit {
    private let manifest: CaptureManifest
    private let budgets: [String: Walkbook.Budgets]

    init(_ manifest: CaptureManifest, budgets: [String: Walkbook.Budgets]) {
        self.manifest = manifest
        self.budgets = budgets
    }

    func evaluate() -> BudgetAuditResult {
        let held = Dictionary(manifest.screens.map { ($0.id, $0) }) { first, _ in first }
        var result = BudgetAuditResult(screens: budgets.count)
        for (id, budget) in budgets.sorted(by: { $0.key < $1.key }) {
            guard let record = held[id] else {
                result.unreachable.append("UNREACHABLE \(id): not captured (not in the bundle)")
                continue
            }
            guard record.outcome.isCaptured, !record.captures.isEmpty else {
                let why = record.outcome.isCaptured ? "no state was captured" : CaptureBundleSummary.outcomeWords(record.outcome)
                result.unreachable.append("UNREACHABLE \(id): not captured (\(why)); route taken: \(record.routeTaken.rendered)")
                continue
            }
            for capture in record.captures {
                check(capture, of: record, against: budget, into: &result)
            }
        }
        return result
    }

    private func check(_ capture: CaptureManifest.StateCapture, of record: CaptureManifest.ScreenRecord, against budget: Walkbook.Budgets, into result: inout BudgetAuditResult) {
        let subject = "\(record.id)/\(capture.state.slug)"
        let route = "route taken: \(record.routeTaken.rendered)"
        guard manifest.isDeviceWalk else {
            result.unreachable.append("UNREACHABLE \(subject): performance is recorded on a device only (this bundle is a simulator walk); \(route)")
            return
        }
        guard let performance = capture.performance else {
            result.unreachable.append("UNREACHABLE \(subject): no performance record (not measured); \(route)")
            return
        }
        for check in checks(of: budget) {
            guard let figure = check.figure.median(in: performance, appBundleID: manifest.appBundleID) else {
                result.unreachable.append("UNREACHABLE \(subject): \(check.key) budget — the record has no \(check.needs); \(route)")
                continue
            }
            if figure.value > Double(check.limit) {
                result.over.append("\(subject): \(check.name) \(Self.render(figure.value, unit: check.unit)) \(check.unit) > budget \(check.limit) \(check.unit) (median of \(figure.count) measurement\(figure.count == 1 ? "" : "s"))")
            } else {
                result.within += 1
            }
        }
    }

    /// A whole figure as an integer; memory to two decimals, so a median just over its budget (65579 kB is 64.04 MB against 64) never prints as equal to it.
    private static func render(_ value: Double, unit: String) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: unit == "MB" ? "%.2f" : "%.1f", value)
    }
}

private extension PerformanceBudgetAudit {
    /// One budget as the rule reads it: what it is called, its limit, what the record has to hold, and the figure it is checked against (whose unit is the budget's).
    struct Check {
        let key: String
        let name: String
        let limit: Int
        let needs: String
        let figure: PerformanceFigure

        var unit: String {
            figure.unit
        }
    }

    func checks(of budget: Walkbook.Budgets) -> [Check] {
        var checks: [Check] = []
        if let limit = budget.launchMs {
            checks.append(Check(key: "launchMs", name: "launch", limit: limit, needs: "first-responsive-frame launch metric (ApplicationFirstFramePresentationResponsive.duration)", figure: .launch))
        }
        if let limit = budget.transitionHitches {
            checks.append(Check(key: "transitionHitches", name: "transition hitches", limit: limit, needs: "navigation transition hitch metric", figure: .transitionHitches))
        }
        if let limit = budget.cpuMs {
            checks.append(Check(key: "cpuMs", name: "CPU time", limit: limit, needs: "CPU time metric for the app", figure: .cpuTime))
        }
        if let limit = budget.memoryPeakMB {
            checks.append(Check(key: "memoryPeakMB", name: "peak memory", limit: limit, needs: "peak physical memory metric for the app", figure: .memoryPeak))
        }
        return checks
    }
}
