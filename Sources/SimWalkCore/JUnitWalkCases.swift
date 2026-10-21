//
// Copyright © Agulhas Labs
//

import Foundation

public struct JUnitWalkCases {
    /// A walk's bundle as test cases: one per screen × state, classname the screen id and name the state's slug.
    ///
    /// A captured state passes — so `tests − failures` is the answer's capture count. A screen whose outcome is `unexpectedScreen` or `buildMismatch` was the wrong screen or the wrong build, so **every** case of it fails with the line the answer prints for it, the captures it filed included. For `captureFailed` and `stateNotApplied` each state keeps its own truth: a captured state passes, and a state the record names as refused fails with the screen's line; when the record names none, the screen stands for the states the walkbook declared in one failing case named `(screen)`, because a walk record does not carry them.
    public static func report(of bundle: CaptureBundle) -> JUnitReport {
        var cases: [JUnitCase] = []
        for (index, screen) in bundle.manifest.screens.enumerated() {
            let wrong = switch screen.outcome {
            case .unexpectedScreen, .buildMismatch: true
            default: false
            }
            let why = screen.outcome.isCaptured ? "" : CaptureBundleSummary.screenLine(screen, position: index + 1).trimmingCharacters(in: .whitespaces)
            cases += screen.captures.map { JUnitCase(classname: screen.id, name: $0.state.slug, result: wrong ? .failed(why) : .passed) }
            guard !screen.outcome.isCaptured else { continue }
            let refused = (screen.refusedStates ?? []).map(\.slug).filter { slug in !screen.captures.contains { $0.state.slug == slug } }
            // A wrong screen's filed captures already fail; it needs the `(screen)` case only when it filed none.
            let needsScreenCase = refused.isEmpty && !(wrong && !screen.captures.isEmpty)
            let names = needsScreenCase ? ["(screen)"] : refused
            cases += names.map { JUnitCase(classname: screen.id, name: $0, result: .failed(why)) }
        }
        return JUnitReport(command: "walk", cases: cases)
    }
}
