//
// Copyright © Agulhas Labs
//

import Foundation

/// Answers `simwalk session step`: the verdict — landed, blocked, or the refusal of a step not taken — then `step: <the landed step's JSON>`, `bound: <the element a tap, scrollTo, type or longPress bound>` where it bound one, `screen <hash>` and the delta.
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
            throw LiveSessionError.snapshotChanged(expected: stepAnswer.expectedHash ?? "", found: stepAnswer.foundHash ?? "", moved: stepAnswer.pixelsMoved)
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
            residue += Self.heldLines(stepAnswer)
            residue.append("step: \(Self.json(landed.asWritten))")
            if let bound = stepAnswer.bound {
                residue.append("bound: \(BundleScreenQuery.line(bound))")
            }
            verdict = .reporting(qualifications: [still].compactMap(\.self), detail: "landed \(landed)\(Self.frameClause(for: landed, root: tree)) — now on root \(BundleScreenQuery.rootClause(tree))")
        case .blocked, .snapshotChanged:
            let reason = stepAnswer.reason.map { " — \($0)" } ?? ""
            residue += Self.heldLines(stepAnswer)
            verdict = .qualified(["blocked: \(sent) did not land\(reason)"] + [still].compactMap(\.self), detail: "nothing added to the route — on root \(BundleScreenQuery.rootClause(tree))")
        }
        residue.append("screen \(ScreenHash.of(tree, pixels: screen.pixels))")
        residue += stepAnswer.delta?.residue ?? []
        return Answer(header: LiveScreenQuery.header(of: screen), verdict: verdict, residue: residue)
    }

    /// The line saying a guard held across a text-less screen's movement (SimWalk#226); none for a step whose guard matched exactly.
    private static func heldLines(_ answer: LiveSessionStepAnswer) -> [String] {
        guard let moved = answer.pixelsMoved, let expected = answer.expectedHash else { return [] }
        return ["guard: held, \(ScreenDelta.percentOfScreen(moved)) of the screen moved since \(expected) (the tree has no text, so the guard allows a picture that moves a little)"]
    }

    /// For a landed `tapPoint` or `drag` without a `label`, the frame its point was taken in (SimWalk#149).
    ///
    /// The tree is rooted at the application element, whose frame is the `app.frame` the runner offsets the touch from, in the interface orientation the app is drawn in. It names the orientation too, because an iPad's screenshot comes back portrait with the content drawn rotated and misleads about which one `at` is in. Nothing when the root's frame is empty.
    static func frameClause(for step: Walkbook.RouteStep, root: AXNode) -> String {
        guard step.isScreenPointStep, root.frame.width > 0, root.frame.height > 0 else {
            return ""
        }
        let orientation = root.frame.width == root.frame.height ? "" : (root.frame.width > root.frame.height ? " (landscape)" : " (portrait)")
        return " in the app's \(TapPointPlacement.size(root.frame)) pt frame\(orientation)"
    }

    /// `step` as a walkbook writes it, on one line.
    static func json(_ step: Walkbook.RouteStep) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(step)).flatMap { String(data: $0, encoding: .utf8) } ?? step.description
    }
}
