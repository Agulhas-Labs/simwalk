//
// Copyright © Agulhas Labs
//

import Foundation

public struct JUnitOracleCases {
    /// An oracle check as test cases: classname the screen id, name `<figure id> · <state slug>`.
    ///
    /// `matches` passes. `matches none`, `not on screen`, no readable number and an oracle failure fail with the figure's rendered line. A figure of a state the walk did not capture fails with "state not captured", and one of a screen it did not capture with "screen not captured" under the name `<figure id> · (screen)`: the text answer counts both in its denominator.
    public static func report(_ summary: OracleSummary) -> JUnitReport {
        let checks = summary.allChecks.map { check in
            let name = "\(check.figureID) · \(check.stateSlug)"
            if case .matches = check.outcome {
                return JUnitCase(classname: check.screenID, name: name, result: .passed)
            }
            return JUnitCase(classname: check.screenID, name: name, result: .failed(check.rendered))
        }
        let unchecked = (summary.uncapturedStateFigures + summary.uncapturedScreenFigures).map {
            JUnitCase(classname: $0.screenID, name: "\($0.figureID) · \($0.stateSlug ?? "(screen)")", result: .failed($0.line))
        }
        return JUnitReport(command: "bundle oracle", cases: checks + unchecked)
    }
}
