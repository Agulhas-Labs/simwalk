//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// A label step against an app label that writes a no-break space where the walkbook has a space (SimWalk#99).
///
/// The specimen is an app's `CO₂ level` row, whose label is `CO₂\u{00A0}level, 38.8 …` so the name never wraps: `tap 'CO₂ level'` read as UNREACHABLE, "nothing on screen is labelled or identified", and its author could not see why.
struct RouteTargetSpacingTests {
    /// The field case: the row is reached, as a spacing match the live predicate cannot return, so it carries no index.
    @Test
    func alabelWithANoBreakSpaceIsReachedByAStepWithASpace() {
        let tree = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 100), label: "CO₂\u{00A0}level, 38.8 ppm")])

        guard case let .chosen(target, _) = RouteTarget.choose(labelled: "CO₂ level", in: tree) else {
            Issue.record("expected the row to be chosen")
            return
        }

        #expect(target.match == .spacing)
        #expect(target.index == nil)
    }

    /// A whole label matches the same way, and a narrow no-break space reads as a space too.
    @Test
    func aNarrowNoBreakSpaceAndAWholeLabelAreReadAsSpacesToo() {
        for label in ["CO₂\u{202F}level, 38.8", "CO₂\u{202F}level", "CO₂\u{00A0}level"] {
            let tree = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 100), label: label)])
            guard case let .chosen(target, _) = RouteTarget.choose(labelled: "CO₂ level", in: tree) else {
                Issue.record("expected '\(label)' to be chosen")
                continue
            }
            #expect(target.match == .spacing, "'\(label)'")
            #expect(target.index == nil, "'\(label)'")
        }
    }

    /// Both sides are read: a walkbook that carries the no-break space reaches an app that writes an ordinary one.
    @Test
    func aStepWithANoBreakSpaceReachesALabelWithASpace() {
        let tree = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 100), label: "CO₂ level, 38.8")])

        guard case let .chosen(target, _) = RouteTarget.choose(labelled: "CO₂\u{00A0}level", in: tree) else {
            Issue.record("expected the row to be chosen")
            return
        }

        #expect(target.match == .spacing)
    }

    /// A byte-exact element anywhere on screen wins over a no-break one, even when it is later in the tree and the other is a control.
    @Test
    func anExactLabelOutranksANoBreakOne() {
        let tree = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 100), label: "CO₂\u{00A0}level, 38.8"),
            AXNode(type: "StaticText", frame: Self.frame(y: 200), label: "CO₂ level"),
        ])

        guard case let .chosen(target, among) = RouteTarget.choose(labelled: "CO₂ level", in: tree) else {
            Issue.record("expected a choice")
            return
        }

        #expect(target.match == .label)
        #expect(target.node.type == "StaticText")
        #expect(among.count == 1)
    }

    /// A spacing match is a tier above a lead-in, which is the last resort.
    @Test
    func aSpacingMatchBeatsALeadIn() {
        let tree = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 100), label: "CO₂ level 38.8 ppm"),
            AXNode(type: "Button", frame: Self.frame(y: 200), label: "CO₂\u{00A0}level, 38.8"),
        ])

        guard case let .chosen(target, _) = RouteTarget.choose(labelled: "CO₂ level", in: tree) else {
            Issue.record("expected a choice")
            return
        }

        #expect(target.match == .spacing)
        #expect(target.node.label == "CO₂\u{00A0}level, 38.8")
    }

    /// A spacing match is not a literal one: it does not settle a step or start its budget, as a pattern does not.
    @Test
    func aSpacingMatchIsNotLiteral() {
        let tree = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 100), label: "CO₂\u{00A0}level, 38.8")])
        let choice = RouteTarget.choose(labelled: "CO₂ level", in: tree)

        #expect(!choice.matchedLiterally)
        #expect(!choice.isSettled)
    }

    /// Identifiers are names the app chose, compared as written.
    @Test
    func anIdentifierIsNotNormalised() {
        let tree = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 100), identifier: "CO₂\u{00A0}level")])

        #expect(RouteTarget.choose(labelled: "CO₂ level", in: tree) == .none)
    }

    /// The refusal names the difference, so the author can see it.
    @Test
    func theDescriptionSaysTheLabelHasANoBreakSpace() {
        let tree = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 100), label: "CO₂\u{00A0}level, 38.8")])

        guard case let .chosen(target, _) = RouteTarget.choose(labelled: "CO₂ level", in: tree) else {
            Issue.record("expected a choice")
            return
        }

        #expect(target.description == "a Button labelled 'CO₂ level, 38.8' (its label differs from the step only in a no-break space)")
    }

    /// The spacing tier is consulted before the `{n}` pattern's: a placeholder step reaches the label that carries it, no-break space and all, before any numbered neighbour.
    @Test
    func aSpacingMatchOutranksAPatternMatch() {
        let tree = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 100), label: "Week 3"),
            AXNode(type: "Button", frame: Self.frame(y: 200), label: "Week\u{00A0}{n}"),
        ])

        guard case let .chosen(target, _) = RouteTarget.choose(labelled: "Week {n}", in: tree) else {
            Issue.record("expected a choice")
            return
        }

        #expect(target.match == .spacing)
        #expect(target.node.label == "Week\u{00A0}{n}")
    }

    private static func screen(_ content: [AXNode]) -> AXNode {
        AXNode(type: "Application", frame: frame(y: 0, height: 874), children: [
            AXNode(type: "Window", frame: frame(y: 0, height: 874), children: content),
        ])
    }

    private static func frame(y: Double, height: Double = 60) -> AXNode.Frame {
        AXNode.Frame(x: 0, y: y, width: 402, height: height)
    }
}
