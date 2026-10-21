//
// Copyright © Agulhas Labs
//

import Foundation

public struct JUnitDiffCases {
    /// A diff as test cases, classname the screen id.
    ///
    /// Each compared state with no counted flag passes under its slug. Each **counted** flag — the ones `flagCount` counts, a layout shift and an Apple audit issue included; a flag the reference has too is printed and never counted — fails as `<slug> · <rule> · <key>` (`<slug> · shift · <element>` for a shift, `<slug> · apple · <rule> · <element>` for an Apple audit issue). A state whose Apple audits could not be compared also gets a skipped `<slug> · apple · not compared` case. A screen or state on one side only, and what was not compared, is skipped with the reason the text answer gives.
    public static func report(_ diff: BundleDiff) -> JUnitReport {
        var cases = diff.unpairedScreens.map {
            JUnitCase(classname: $0.id, name: "(screen)", result: .skipped("\($0.side.rawValue) only"))
        }
        for screen in diff.screens {
            guard screen.isCompared else {
                let reference = CaptureBundleSummary.outcomeWords(screen.referenceOutcome)
                let run = CaptureBundleSummary.outcomeWords(screen.runOutcome)
                cases.append(JUnitCase(classname: screen.id, name: "(screen)", result: .skipped("not compared — reference \(reference), run \(run)")))
                continue
            }
            cases += screen.unpairedStates.map {
                JUnitCase(classname: screen.id, name: $0.slug, result: .skipped("\($0.side.rawValue) only — \($0.screenshotPath)"))
            }
            let shifts = screen.shiftFlags ?? []
            let apples = screen.appleFlags ?? []
            let lost = diff.appleNotCompared.filter { $0.screenID == screen.id }
            for state in screen.states {
                let stateShifts = shifts.filter { $0.slug == state.slug }
                let shiftCases = stateShifts.map { flag in
                    let element = BundleDiffRendering.elementText(flag.shift.element)
                    return JUnitCase(classname: screen.id, name: "\(state.slug) · shift · \(element)", result: .failed("shift only in \(flag.side.rawValue): \(element) moved \(BundleDiffRendering.moveText(flag.shift)) pt — cause: \(BundleDiffRendering.causeText(flag.shift.cause))"))
                }
                let appleCases = apples.filter { $0.slug == state.slug }.map { flag in
                    let element = BundleDiffRendering.appleElementText(flag)
                    return JUnitCase(classname: screen.id, name: "\(state.slug) · apple · \(flag.rule) · \(element)", result: .failed("apple \(flag.rule): \(element) — \(flag.compactDescription), not in reference"))
                }
                // `ShiftDiff` reads manifest motion records, not trees, so a shift on a state whose tree could not be read is still counted by `flagCount`.
                if let side = [(BundleDiff.Side.reference, state.reference), (.run, state.run)].first(where: { $0.1.unreadable != nil }), let reason = side.1.unreadable {
                    cases.append(JUnitCase(classname: screen.id, name: state.slug, result: .skipped("not compared — the \(side.0.rawValue)'s tree could not be read: \(reason)")))
                    cases += shiftCases + appleCases + notComparedCases(lost, state.slug, screen.id)
                    continue
                }
                let counted = state.flags.filter { !$0.isInherited }
                if counted.isEmpty, stateShifts.isEmpty, appleCases.isEmpty {
                    cases.append(JUnitCase(classname: screen.id, name: state.slug, result: .passed))
                }
                cases += counted.map {
                    JUnitCase(classname: screen.id, name: "\(state.slug) · \($0.rule) · \($0.key)", result: .failed(BundleDiffRendering.flagLine($0, screenshot: state.run.screenshotPath)))
                }
                cases += shiftCases + appleCases + notComparedCases(lost, state.slug, screen.id)
            }
        }
        return JUnitReport(command: "bundle diff", cases: cases)
    }

    /// The one skipped case for a state whose Apple audits could not be compared.
    private static func notComparedCases(_ lost: [BundleDiff.AppleNotCompared], _ slug: String, _ screenID: String) -> [JUnitCase] {
        lost.filter { $0.slug == slug }.map {
            JUnitCase(classname: screenID, name: "\(slug) · apple · not compared", result: .skipped("apple audit not compared — \($0.reason)"))
        }
    }
}
