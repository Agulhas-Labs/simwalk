//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// A `tab` step finds its button on a `TabBar` or on iPad's floating tab bar (SimWalk#109).
struct TabTargetTests {
    private static func frame(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> AXNode.Frame {
        AXNode.Frame(x: x, y: y, width: width, height: height)
    }

    private static func node(
        _ type: String,
        _ label: String? = nil,
        at frame: AXNode.Frame = frame(0, 0, 10, 10),
        identifier: String? = nil,
        selected: Bool = false,
        children: [AXNode] = []
    ) -> AXNode {
        AXNode(type: type, frame: frame, label: label, identifier: identifier, isSelected: selected, children: children)
    }

    /// A tab button as iPad draws it: an outer button holding an inner twin with the same label, identifier and frame.
    private static func tab(_ label: String, x: Double, y: Double = 36, selected: Bool = false) -> AXNode {
        let box = frame(x, y, 70, 36)
        let inner = node("Button", label, at: box, identifier: "sym.\(label)")
        return node("Button", label, at: box, identifier: "sym.\(label)", selected: selected, children: [inner])
    }

    private static func floatingBar(y: Double = 36, selected: String? = "Rows") -> AXNode {
        let labels = ["Toggle sidebar", "Hub", "Rows", "Menus", "Nested"]
        let buttons = labels.enumerated().map { index, label in
            tab(label, x: 332 + Double(index) * 80, y: y, selected: label == selected)
        }
        return node("Other", at: frame(0, y - 4, 1032, 44), children: buttons)
    }

    private static func screen(_ children: AXNode...) -> AXNode {
        node("Window", at: frame(0, 0, 1032, 1376), children: [node("Other", children: children)])
    }

    private static func tabBar() -> AXNode {
        let buttons = ["Hub", "Rows"].enumerated().map { index, label in
            node("Button", label, at: frame(Double(index) * 100, 791, 100, 49), selected: index == 0)
        }
        return node("TabBar", "Tab Bar", at: frame(0, 791, 402, 83), children: [node("Other", children: [node("Other", children: buttons)])])
    }

    @Test
    func aTabBarButtonIsFoundOnTheTabBar() {
        let result = TabTarget.locate("Rows", in: Self.screen(Self.tabBar()))

        guard case let .found(button, bar) = result else {
            Issue.record("expected found, got \(result)")
            return
        }

        #expect(button.label == "Rows")
        #expect(bar == .tabBar)
    }

    @Test
    func aTabIsFoundOnTheFloatingBarAsTheOuterButton() {
        let result = TabTarget.locate("Menus", in: Self.screen(Self.floatingBar()))

        guard case let .found(button, bar) = result else {
            Issue.record("expected found, got \(result)")
            return
        }

        #expect(bar == .floating)
        #expect(button.children.count == 1, "the outer button, not its inner twin")
    }

    @Test
    func anIdentifierNamesATabToo() {
        let result = TabTarget.locate("sym.Hub", in: Self.screen(Self.floatingBar()))

        guard case .found = result else {
            Issue.record("expected found, got \(result)")
            return
        }
    }

    @Test
    func anUnknownLabelListsTheFloatingBarsButtons() {
        let result = TabTarget.locate("Nope", in: Self.screen(Self.floatingBar()))

        #expect(result == .missing(tabs: ["Hub", "Rows", "Menus", "Nested"], bar: .floating))
    }

    /// **The sidebar toggle is no tab** (#119, a spec change: it used to be listed, and `tab 'Toggle sidebar'` tapped it).
    @Test
    func theSidebarToggleIsNotATab() {
        let result = TabTarget.locate("Toggle sidebar", in: Self.screen(Self.floatingBar()))

        #expect(result == .missing(tabs: ["Hub", "Rows", "Menus", "Nested"], bar: .floating))
    }

    @Test
    func aRowWithNoSelectedButtonIsNotATabBar() {
        let result = TabTarget.locate("Hub", in: Self.screen(Self.floatingBar(selected: nil)))

        #expect(result == .missing(tabs: [], bar: nil))
    }

    @Test
    func aSegmentedControlIsNotATabBar() {
        let segments = Self.floatingBar().children
        let picker = Self.node("SegmentedControl", at: Self.frame(0, 32, 1032, 44), children: segments)

        #expect(TabTarget.locate("Hub", in: Self.screen(picker)) == .missing(tabs: [], bar: nil))
    }

    @Test
    func theTopmostOfTwoGroupsWins() {
        let lower = Self.floatingBar(y: 500, selected: "Hub")
        let result = TabTarget.locate("Hub", in: Self.screen(lower, Self.floatingBar(y: 36)))

        guard case let .found(button, _) = result else {
            Issue.record("expected found, got \(result)")
            return
        }

        #expect(button.frame.y == 36)
    }

    @Test
    func aTabBarWinsOverAFloatingGroup() {
        let result = TabTarget.locate("Hub", in: Self.screen(Self.floatingBar(), Self.tabBar()))

        guard case let .found(_, bar) = result else {
            Issue.record("expected found, got \(result)")
            return
        }

        #expect(bar == .tabBar)
    }
}
