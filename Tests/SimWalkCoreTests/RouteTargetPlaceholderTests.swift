//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// A filled SwiftUI `TextField("Nickname", …)` exposes its title as the placeholder and nothing else, so a `type` step finds a field by its placeholder when nothing carries the label (SimWalk#212).
struct RouteTargetPlaceholderTests {
    @Test
    func aTypeStepFindsAFieldThatOnlyHasAPlaceholder() {
        let tree = Self.screen([
            Self.field(y: 200, value: "Draft", placeholder: "Nickname"),
        ])

        let choice = RouteTarget.choose(labelled: "Nickname", in: tree, reaching: .textEntry)

        guard case let .chosen(target, _) = choice else {
            Issue.record("expected the field to be chosen, got \(choice)")
            return
        }

        #expect(target.match == .placeholder)
        #expect(target.node.value == "Draft")
        #expect(!choice.isSettled)
        #expect(choice.acceptsOnceStill)
    }

    @Test
    func aLabelledFieldBeatsAPlaceholderMatchWhereverItSits() {
        let tree = Self.screen([
            Self.field(y: 200, placeholder: "Nickname"),
            Self.field(y: 260, label: "Nickname"),
        ])

        guard case let .chosen(target, _) = RouteTarget.choose(labelled: "Nickname", in: tree, reaching: .textEntry) else {
            Issue.record("expected the labelled field")
            return
        }

        #expect(target.match == .label)
        #expect(target.node.frame.y == 260)
    }

    @Test
    func twoFieldsWithTheSamePlaceholderAreATie() {
        let tree = Self.screen([
            Self.field(y: 200, placeholder: "Nickname"),
            Self.field(y: 260, placeholder: "Nickname"),
        ])

        guard case let .ambiguous(fields) = RouteTarget.choose(labelled: "Nickname", in: tree, reaching: .textEntry) else {
            Issue.record("expected a refusal")
            return
        }

        #expect(fields.count == 2)
    }

    @Test
    func aPlaceholderIsMatchedWholeAndNeverByItsStart() {
        let tree = Self.screen([Self.field(y: 200, placeholder: "Nickname")])

        #expect(RouteTarget.choose(labelled: "Nick", in: tree, reaching: .textEntry) == .none)
    }

    @Test
    func aTapDoesNotMatchByPlaceholder() {
        let tree = Self.screen([Self.field(y: 200, placeholder: "Nickname")])

        #expect(RouteTarget.choose(labelled: "Nickname", in: tree, reaching: .control) == .none)
        #expect(RouteTarget.choose(labelled: "Nickname", in: tree, reaching: .anything) == .none)
        #expect(!RouteTarget.matches("Nickname", tree.children[0]))
    }

    private static func field(y: Double, label: String? = nil, value: String? = nil, placeholder: String? = nil) -> AXNode {
        AXNode(type: "TextField", frame: AXNode.Frame(x: 0, y: y, width: 402, height: 44), label: label, value: value, placeholder: placeholder)
    }

    private static func screen(_ children: [AXNode]) -> AXNode {
        AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), children: children)
    }
}
