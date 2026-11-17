//
// Copyright © Agulhas Labs
//

import SimWalkCore
import UIKit
import XCTest

/// Resolving a step's label to the live element it acts on, split from `StepPerformer` for its size (SimWalk#119): the reads that choose a candidate, the seek that swipes towards an absent one, and the binding of the choice to an `XCUIElement`.
@MainActor
struct TargetResolution {
    /// Resolves a label, swiping up and reading again while nothing carries it (SimWalk#74, #104): `ScrollSearch.resolveSeeking`, which holds the loop, over this type's `resolve` and the app's tree and swipe.
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
            swipe: { swipe(app, $0) }
        )
    }

    /// Swipes `app` once the way `direction` says (SimWalk#280).
    static func swipe(_ app: XCUIApplication, _ direction: ScrollSearch.Direction) {
        switch direction {
        case .up: app.swipeUp()
        case .down: app.swipeDown()
        }
    }

    /// A live frame as the tree writes frames.
    static func frame(_ live: CGRect) -> AXNode.Frame {
        AXNode.Frame(x: Double(live.minX), y: Double(live.minY), width: Double(live.width), height: Double(live.height))
    }

    /// Reads the screen until `RouteTargetTracker` says the answer for `label` cannot improve, and answers that choice.
    ///
    /// Two waits, because a screen arrives in two parts: nothing literal matching gets the lookup timeout a query's `waitForExistence` always had — a `{n}` pattern or a lead-in is acted on only once that has run out — and something literal matching that is not yet the answer — the navigation bar a pushed screen draws at once — gets the step's settle budget more for the row that arrives a beat after it. A bar control is taken sooner, once the hierarchy has held still for the quiet period (SimWalk#24). Every one of those decisions is the tracker's, in the core, where a test replays it against scripted reads; this loop keeps only the reads and the clock.
    ///
    /// `lookup` is the step's lookup timeout everywhere but inside `bind`, which passes what is left of its own so that one bind never reads for longer than one lookup in all.
    static func resolve(
        _ label: String,
        reaching reach: RouteTarget.Reach,
        in app: XCUIApplication,
        quiet: TimeInterval,
        budget: TimeInterval,
        lookup: TimeInterval = StepPerformer.timeout
    ) throws -> RouteTarget.Choice {
        var tracker = RouteTargetTracker(label: label, reaching: reach, quiet: quiet, budget: budget, lookup: lookup, interval: StepPerformer.settleInterval)
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
    /// An element bound where the snapshot read it costs nothing more. One that is not there is read again until it holds steady (SimWalk#255): a walk turns UIKit's animations off but not SwiftUI's, so a button on a panel a spring is still sliding in has moved between the read and the bind, and the next step used to meet it in flight and refuse it as moved. Each read chooses the step's label again (`RouteTarget.Choice.following`) — the same element, at any tier, at its new label or frame — and `MovingTargetSettle` binds it once it has held steady for the screen's quiet period, or refuses it as having kept moving once the lookup runs out. A first read that finds it steady with where the snapshot did binds at once: the snapshot came after the screen's quiet period, so a still screen whose `{n}` chip or lead-in ticked pays that one read, as before the wait existed, and only an element that really moved waits. When a read finds a different element, the screen is read until the tracker settles once more, within what is left of the lookup; a different element both times is refused, naming both; anything else is the miss, reported as the element having moved. A read that settles but whose element the binder then cannot bind is not refused at once either: `MovingTargetSettle.missedBind()` starts the quiet period again, and only the lookup running out refuses the step (SimWalk#276). The same element is answered with the choice that found it, so a step that then fails to land reports what it actually acted on.
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
        let lookup = StepPerformer.timeout
        var settle = MovingTargetSettle(quiet: quiet, lookup: lookup, interval: StepPerformer.settleInterval, snapshot: target.node.frame)
        let started = Date()
        var missedBind = false
        while true {
            var rebinding = try choice.following(labelled: label, in: AXTreeCapture.tree(of: app))
            if case .different = rebinding {
                let left = max(0, lookup - Date().timeIntervalSince(started))
                rebinding = try choice.rebinding(to: resolve(label, reaching: target.reach, in: app, quiet: quiet, budget: budget, lookup: left))
            }
            if case .different = rebinding {
                return .refused(rebinding.reason)
            }
            let fresh: RouteTarget.Choice? = if case let .same(fresh) = rebinding {
                fresh
            } else {
                nil
            }
            let retarget: RouteTarget.Candidate? = if case let .chosen(retarget, _)? = fresh {
                retarget
            } else {
                nil
            }
            switch settle.next(frame: retarget?.node.frame, elapsed: Date().timeIntervalSince(started)) {
            case .watch:
                Thread.sleep(forTimeInterval: StepPerformer.settleInterval)
            case .steady:
                guard let fresh, let retarget, let element = binder(retarget) else {
                    missedBind = true
                    settle.missedBind()
                    Thread.sleep(forTimeInterval: StepPerformer.settleInterval)
                    continue
                }
                return .element(element, retarget, fresh)
            case .gone:
                return .moved(target)
            case let .outOfTime(seconds):
                return missedBind ? .unbound(target, seconds: seconds) : .keptMoving(target, seconds: seconds)
            }
        }
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

    /// Among `query`, the element carrying exactly the label the snapshot recorded — or, for a candidate matched by identifier, that identifier — at a frame steady with the one it recorded (`frame(_:matches:)`).
    ///
    /// **Both, never the frame alone.** List rows are drawn alike, so a row inserted between the read and the bind puts its neighbour at precisely the recorded frame; a frame-only search would tap the neighbour and the step's arrival check would pass. And the label in the predicate keeps the query small: the frame is read one element at a time, which across every descendant of a real screen is dozens of resolutions per tap. An element whose label changed in the moment between the two is not bound here at all: a `{n}` pattern or a lead-in is then chosen again from one fresh read (`bind`), and anything else says it moved — which it did.
    static func recorded(_ target: RouteTarget.Candidate, among query: XCUIElementQuery) -> XCUIElement? {
        let predicate: NSPredicate
        if target.match == .placeholder, let placeholder = target.node.placeholder {
            predicate = NSPredicate(format: "placeholderValue == %@", placeholder)
        } else if target.match == .identifier, let identifier = target.node.identifier {
            predicate = NSPredicate(format: "identifier == %@", identifier)
        } else if let label = target.node.label {
            predicate = NSPredicate(format: "label == %@", label)
        } else {
            return nil
        }
        let frame = target.node.frame
        return query.matching(predicate).allElementsBoundByIndex.first { Self.frame($0.frame, matches: frame) }
    }

    /// Whether a live element's frame is the one the snapshot recorded for a step's target: steady with it (`AXNode.Frame.isSteady(with:)`), not equal to it.
    ///
    /// **Steady, because some elements never stop moving** (SimWalk#252, #255): a walk turns UIKit's animations off but not SwiftUI's, and an endless pulse scales an element a few percent on every read, so a half-point match missed it at whatever phase the bind read it and the step refused it as moved. A neighbouring row of the same label still sits a whole row away, far outside the allowance. Only a target's bind uses it; bars are matched exactly (`frame(_:exactlyMatches:)`).
    static func frame(_ live: CGRect, matches recorded: AXNode.Frame) -> Bool {
        AXNode.Frame(x: Double(live.origin.x), y: Double(live.origin.y), width: Double(live.size.width), height: Double(live.size.height)).isSteady(with: recorded)
    }

    /// Whether a live element's frame is the one a read recorded to within half a point: for a tab bar's button and for a bar's twins (`BarClearance`), which the steady match was never specified for.
    ///
    /// **Exact, because nearness is wrong there.** A bar from another layer (a cover's over the one behind) can sit within the steady allowance of the one read, and counting it as a twin would let its hit test answer for the wrong bar; a tab button's bind already rereads its own fresh frame until the deadline, so it never needed the allowance.
    static func frame(_ live: CGRect, exactlyMatches recorded: AXNode.Frame) -> Bool {
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
