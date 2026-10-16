//
// Copyright © Agulhas Labs
//

import Foundation

/// The `motionBudget` rule of `bundle audit` (SimWalk#67, M3): holds each screen the walkbook gives `budgets` to against the motion its captures recorded.
///
/// **Opt-in, and the only rule that reads the manifest rather than the trees.** A budget is a value judgement the walkbook makes, so the rule runs only for the screens that state one; a bundle audited without a walkbook, or with a walkbook that states none, does not run it, and the section's heading says so (`BundleAuditSummary`).
///
/// **A budget is never "within budget" without a measurement.** A screen that was not captured, a capture walked without motion, and a layout-shift budget over a record that predates shifts are each UNREACHABLE, naming the screen, the state and the route the walk took, and qualify the verdict as a finding does. A settle that never happened (`settleMilliseconds` absent: the watch ran out unsettled) is over every settle budget, since the measurement is that there was none.
struct MotionBudgetAudit {
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
        guard let motion = capture.motion else {
            result.unreachable.append("UNREACHABLE \(subject): no motion record (walked without motion); route taken: \(record.routeTaken.rendered)")
            return
        }
        if let limit = budget.settleMs {
            if let settle = motion.settleMilliseconds {
                if settle > limit {
                    result.over.append("\(subject): settle \(settle) ms > budget \(limit) ms (reads every \(motion.readIntervalMilliseconds) ms)")
                } else {
                    result.within += 1
                }
            } else {
                result.over.append("\(subject): never settled within the watch (\(motion.readCount) reads, every \(motion.readIntervalMilliseconds) ms)")
            }
        }
        if let limit = budget.layoutShifts {
            if let shifts = motion.shifts {
                if shifts.count > limit {
                    let named = shifts.map(Self.describe).joined(separator: "; ")
                    result.over.append("\(subject): \(shifts.count) layout shift\(shifts.count == 1 ? "" : "s") > budget \(limit): \(named)")
                } else {
                    result.within += 1
                }
            } else {
                result.unreachable.append("UNREACHABLE \(subject): layoutShifts budget — motion recorded before layout shifts were; route taken: \(record.routeTaken.rendered)")
            }
        }
    }

    private static func describe(_ shift: CaptureManifest.Motion.Shift) -> String {
        let cause = shift.cause.map { "caused by \($0.change.rawValue) \(name($0.element))" } ?? "no cause named"
        return "\(name(shift.element)) (\(cause))"
    }

    private static func name(_ element: CaptureManifest.Motion.Element) -> String {
        if let label = element.label {
            return "\(element.type) '\(AuditRowFormat.trim(label))'"
        }
        return element.within.map { "\(element.type) in '\(AuditRowFormat.trim($0))'" } ?? element.type
    }
}
