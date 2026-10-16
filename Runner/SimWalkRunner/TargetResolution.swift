//
// Copyright © Agulhas Labs
//

import SimWalkCore
import UIKit
import XCTest

/// Resolving a step's label to the live element it acts on, split from `StepPerformer` for its size (SimWalk#119): the reads that choose a candidate, the seek that swipes towards an absent one, and the binding of the choice to an `XCUIElement`.
@MainActor
struct TargetResolution {
    /// Resolves a label, swiping up and reading again while nothing carries it (SimWalk#74, #104): `ScrollSearch.resolveSeeking`, which holds the loop, over this enum's `resolve` and the app's tree and swipe.
    static func resolveSeeking(
        _ label: String,
        reaching reach: RouteTarget.Reach,
        search: inout ScrollSearch,
        in app: XCUIApplication,
        quiet: TimeInterval,
        budget: TimeInterval
    ) throws -> (choice: RouteTarget.Choice, stopped: String?) {
        try search.resolveSeeking(
            reaching: reach,
            resolve: { try resolve(label, reaching: reach, in: app, quiet: quiet, budget: budget) },
            read: { try AXTreeCapture.tree(of: app) },
            swipe: { app.swipeUp() }
        )
    }

    /// Reads the screen until `RouteTargetTracker` says the answer for `label` cannot improve, and answers that choice.
    ///
    /// Two waits, because a screen arrives in two parts: nothing literal matching gets the lookup timeout a query's `waitForExistence` always had — a `{n}` pattern or a lead-in is acted on only once that has run out — and something literal matching that is not yet the answer — the navigation bar a pushed screen draws at once — gets the step's settle budget more for the row that arrives a beat after it. A bar control is taken sooner, once the hierarchy has held still for the quiet period (SimWalk#24). Every one of those decisions is the tracker's, in the core, where a test replays it against scripted reads; this loop keeps only the reads and the clock.
    static func resolve(
        _ label: String,
        reaching reach: RouteTarget.Reach,
        in app: XCUIApplication,
        quiet: TimeInterval,
        budget: TimeInterval
    ) throws -> RouteTarget.Choice {
        var tracker = RouteTargetTracker(label: label, reaching: reach, quiet: quiet, budget: budget, lookup: StepPerformer.timeout, interval: StepPerformer.settleInterval)
        let started = Date()
        while true {
            let tree = try AXTreeCapture.tree(of: app)
            if case let .act(choice) = tracker.next(tree: tree, elapsed: Date().timeIntervalSince(started)) {
                return choice
            }
            Thread.sleep(forTimeInterval: StepPerformer.settleInterval)
        }
    }

    /// The live element for what `choice` chose, bound by `binder` — or why the step acts on nothing.
    ///
    /// When a spacing match, a `{n}` pattern or a lead-in has moved on, the step's label is chosen again (`RouteTarget.Choice.rebinding`): from one fresh read, and — when that finds a different element — from reads until the tracker settles once more. The same element at its new label is bound and answered with the choice that found it, so a step that then fails to land reports what it actually acted on; a different element both times is refused, naming both; anything else is the miss, reported as the element having moved.
    static func bind(
        _ choice: RouteTarget.Choice,
        labelled label: String,
        in app: XCUIApplication,
        quiet: TimeInterval,
        budget: TimeInterval,
        by binder: (RouteTarget.Candidate) -> XCUIElement?
    ) throws -> StepPerformer.Binding {
        guard case let .chosen(target, _) = choice else { return .refused(choice.reason(for: label)) }
        if let element = binder(target) {
            return .element(element, target, choice)
        }
        var rebinding = try choice.rebinding(labelled: label, in: AXTreeCapture.tree(of: app))
        if case .different = rebinding {
            rebinding = try choice.rebinding(to: resolve(label, reaching: target.reach, in: app, quiet: quiet, budget: budget))
        }
        switch rebinding {
        case let .same(fresh):
            guard case let .chosen(retarget, _) = fresh, let element = binder(retarget) else { break }
            return .element(element, retarget, fresh)
        case .different:
            return .refused(rebinding.reason)
        case .final:
            break
        }
        return .moved(target)
    }

    /// The live element for a candidate the snapshot chose: bound at its index among the same query's matches, and checked by its frame, falling back to a search by frame when the two orders disagree.
    ///
    /// **A spacing match, a `{n}` pattern or a lead-in has no index to bind at** (`RouteTarget.Candidate.index` is `nil`): `labelPredicate` cannot express any of them, so such an element is not among its results at all. It is bound by the label and frame the snapshot recorded instead (`recorded(_:among:)`).
    static func element(for target: RouteTarget.Candidate, labelled label: String, in app: XCUIApplication) -> XCUIElement? {
        guard let index = target.index else {
            return recorded(target, among: app.descendants(matching: .any))
        }
        let frame = target.node.frame
        let query = app.descendants(matching: .any).matching(labelPredicate(label))
        let bound = query.element(boundBy: index)
        if bound.exists, Self.frame(bound.frame, matches: frame) {
            return bound
        }
        return query.allElementsBoundByIndex.first { Self.frame($0.frame, matches: frame) }
    }

    /// The field a `type` step chose, bound among the text fields of its own type by the label and frame the snapshot recorded.
    ///
    /// **Typed queries rather than `descendants(matching: .any)`**, as the lookup always was here: `app.searchFields` and its siblings are the indexed collections XCUITest is built to answer, and an `.any` query narrowed by element type timed out against a real app and then hung for ten minutes against Settings.
    static func textEntry(for target: RouteTarget.Candidate, in app: XCUIApplication) -> XCUIElement? {
        let fields: XCUIElementQuery? = switch target.node.type {
        case "SearchField": app.searchFields
        case "TextField": app.textFields
        case "SecureTextField": app.secureTextFields
        case "TextView": app.textViews
        default: nil
        }
        return fields.flatMap { recorded(target, among: $0) }
    }

    /// Among `query`, the element carrying exactly the label the snapshot recorded — or, for a candidate matched by identifier, that identifier — at exactly the frame it recorded.
    ///
    /// **Both, never the frame alone.** List rows are drawn alike, so a row inserted between the read and the bind puts its neighbour at precisely the recorded frame; a frame-only search would tap the neighbour and the step's arrival check would pass. And the label in the predicate keeps the query small: the frame is read one element at a time, which across every descendant of a real screen is dozens of resolutions per tap. An element whose label changed in the moment between the two is not bound here at all: a `{n}` pattern or a lead-in is then chosen again from one fresh read (`bind`), and anything else says it moved — which it did.
    static func recorded(_ target: RouteTarget.Candidate, among query: XCUIElementQuery) -> XCUIElement? {
        let predicate: NSPredicate
        if target.match == .identifier, let identifier = target.node.identifier {
            predicate = NSPredicate(format: "identifier == %@", identifier)
        } else if let label = target.node.label {
            predicate = NSPredicate(format: "label == %@", label)
        } else {
            return nil
        }
        let frame = target.node.frame
        return query.matching(predicate).allElementsBoundByIndex.first { Self.frame($0.frame, matches: frame) }
    }

    static func frame(_ live: CGRect, matches recorded: AXNode.Frame) -> Bool {
        abs(Double(live.origin.x) - recorded.x) < 0.5
            && abs(Double(live.origin.y) - recorded.y) < 0.5
            && abs(Double(live.size.width) - recorded.width) < 0.5
            && abs(Double(live.size.height) - recorded.height) < 0.5
    }

    /// Exact label, exact identifier, or a leading comma-separated component — the live predicate a candidate with an index is bound through, and the one `RouteTarget` mirrors over a snapshot for those three matches.
    ///
    /// **Subscripting a query by a string matches the `identifier`, not the label** — which is not what a walkbook means. `Walkbook.RouteStep` documents its payload as the *accessibility label*, the thing an author can see on screen, and most elements in a real app carry no identifier at all. Matching on identifier alone is why a step naming a plainly visible row came back UNREACHABLE in the first spike run.
    ///
    /// **A leading component counts as a match, and that is what keeps a walkbook from rotting.** SwiftUI composes a row's label from its whole subtree, so a Browse category arrives as `Wind, kn, mean kn, gusts, 13` — with a trailing count that is *live data*. A walkbook pinned to the whole string breaks when the data changes rather than when the UI does, which is the opposite of what a walk is for. So `tap 'Wind'` matches a label beginning `Wind, `, while the full string still matches exactly for an author who wants it pinned. The comma-space boundary is the point: it is a component separator, not a prefix, so `Wind` cannot quietly match `Windward`.
    static func labelPredicate(_ label: String) -> NSPredicate {
        NSPredicate(format: "label == %@ OR identifier == %@ OR label BEGINSWITH %@", label, label, "\(label), ")
    }
}
