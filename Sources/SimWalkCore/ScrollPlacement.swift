//
// Copyright © Agulhas Labs
//

import Foundation

/// A `scrollTo` with a `position` bringing its element to the top of the scroll container it sits in, once the search and the bar clearance have landed it (SimWalk#270).
///
/// **The target** is the element's top edge ``margin`` points below the top of the visible part of its container: the container's frame clipped to the screen, less any bar in front of its top (a navigation bar the list scrolls under). **A move** is one slow drag along the container's middle, `slop` points longer than the distance the content must travel (a drag moves nothing until it has travelled that far, as for ``ScrollClearance``), clamped to the visible height less a margin at each end so it begins and ends inside the container. The runner takes at most ``maxDrags`` of them and stops early when a drag moved the element by less than ``leastMovement`` (the end of the list), and this decides nothing about that; it holds the geometry only, so a test replays it without a device.
public struct ScrollPlacement {
    /// How far below the top of the visible container the element's top edge is put, in points.
    public static let margin = 16.0
    /// How near the target the element's top edge may be and the step be done, in points.
    public static let tolerance = 8.0
    /// The most drags one step takes.
    public static let maxDrags = 4
    /// The least a drag must move the element for the list to be taken as having more to give, in points.
    public static let leastMovement = 1.0
    /// How far a drag travels before the content follows it, in points (the figure ``ScrollClearance`` measured).
    public static let slop = 62.0 // The first drag's; ``Loop`` adapts it.

    /// The y at which the element's top edge should rest: ``margin`` below the top of the visible part of `container`, under any of `bars` that cover that top.
    public static func targetY(container: AXNode.Frame, bars: [AXNode.Frame], screen: AXNode.Frame) -> Double {
        visibleTop(container: container, bars: bars, screen: screen) + margin
    }

    /// The next drag, or `.done`, given the element's `frame` now.
    ///
    /// `bars` are the bars in front of the container's top that the runner found hittable, as ``ScrollClearance`` asks; a bar in the lower half of the screen is not one that covers a top, and is ignored.
    public static func next(element: AXNode.Frame, container: AXNode.Frame, bars: [AXNode.Frame], screen: AXNode.Frame, slop: Double = slop) -> Move {
        let top = visibleTop(container: container, bars: bars, screen: screen)
        let bottom = min(container.maxY, screen.maxY)
        let target = top + margin
        let distance = element.minY - target
        guard abs(distance) > tolerance else {
            return .done
        }
        // The range a drag may start and end inside, so it begins on neither a bar nor the container's edge.
        let low = top + margin
        let high = max(low, bottom - margin)
        let drag = min(abs(distance) + slop, high - low)
        let direction = distance > 0 ? -1.0 : 1.0
        let middle = (low + high) / 2
        let x = max(container.minX, screen.minX) + (min(container.maxX, screen.maxX) - max(container.minX, screen.minX)) / 2
        return .drag(x: x, fromY: middle - direction * drag / 2, toY: middle + direction * drag / 2)
    }

    /// The frame of the nearest scroll container above `element` in `tree`, or `nil` where the element sits in none.
    ///
    /// The element is found in the tree by its type, label, identifier and a frame steady with `element.frame` (the live read, which a scroll has moved since the snapshot); the deepest such match is taken.
    public static func containerFrame(of element: AXNode, in tree: AXNode) -> AXNode.Frame? {
        var best: [AXNode]?
        func visit(_ node: AXNode, path: [AXNode]) {
            if node.type == element.type, node.label == element.label, node.identifier == element.identifier, node.frame.isSteady(with: element.frame) {
                best = path
            }
            for child in node.children {
                visit(child, path: path + [node])
            }
        }
        visit(tree, path: [])
        return best?.last { ScrollSearch.scrollContainerTypes.contains($0.type) }?.frame
    }

    /// The bars in `tree` (a tab bar, toolbar or navigation bar shorter than half the screen), which the runner asks whether each is in front before handing their frames to ``next(element:container:bars:screen:slop:)``.
    public static func bars(in tree: AXNode) -> [AXNode] {
        let screen = tree.screenBounds
        return tree.flattened.filter { RouteTarget.isBar($0, on: screen) }
    }

    private static func visibleTop(container: AXNode.Frame, bars: [AXNode.Frame], screen: AXNode.Frame) -> Double {
        let visible = max(container.minY, screen.minY)
        let covering = bars.filter { $0.minY < visible + margin && $0.maxY > visible && $0.minY + $0.height / 2 < screen.minY + screen.height / 2 }
        return max(visible, covering.map(\.maxY).max() ?? visible)
    }
}

public extension ScrollPlacement {
    /// The loop a step runs, as a pure state machine, with the slop it has learned (SimWalk#270 review).
    ///
    /// The slop differs by device and list (62 pt was measured once), and a fixed one overshoots each correction by the difference, alternating sides and leaving the element under a bar. So the loop carries it: a drag that carried the element across the target measured it, as the drag's distance less how far the element moved (floored at 0), and that is the next drag's slop. A drag that moved the element by less than ``ScrollPlacement/leastMovement`` while it was not yet within tolerance doubles the slop once (the drag may have fallen short of it, as ``ScrollClearance`` doubles a drag that moved nothing); a second such drag is the end of the list. At most ``ScrollPlacement/maxDrags`` drags are made.
    struct Loop: Sendable {
        /// The slop the next drag adds to the distance, in points.
        public private(set) var slop: Double
        /// The drags made so far.
        public private(set) var drags = 0
        private var lastTop: Double?
        private var lastDistance = 0.0
        private var lastOffset = 0.0
        private var doubled = false

        public init(slop: Double = ScrollPlacement.slop) {
            self.slop = slop
        }

        /// The next move given the element's `frame` now, or `.ended` where the drags are spent or the list will not move.
        public mutating func next(element: AXNode.Frame, container: AXNode.Frame, bars: [AXNode.Frame], screen: AXNode.Frame) -> Move {
            let offset = element.minY - ScrollPlacement.targetY(container: container, bars: bars, screen: screen)
            if abs(offset) <= ScrollPlacement.tolerance {
                return .done
            }
            if let lastTop {
                let moved = abs(element.minY - lastTop)
                if moved < ScrollPlacement.leastMovement {
                    guard !doubled else {
                        return .ended
                    }
                    doubled = true
                    slop *= 2
                } else if offset * lastOffset < 0 {
                    slop = max(0, lastDistance - moved)
                }
            }
            guard drags < ScrollPlacement.maxDrags else {
                return .ended
            }
            let move = ScrollPlacement.next(element: element, container: container, bars: bars, screen: screen, slop: slop)
            guard case let .drag(_, fromY, toY) = move else {
                return move
            }
            drags += 1
            lastTop = element.minY
            lastOffset = offset
            lastDistance = abs(toY - fromY)
            return move
        }
    }

    /// The next move for placing an element at the top.
    enum Move: Equatable, Sendable {
        /// The element's top edge is within ``tolerance`` of the target.
        case done
        /// Press at `fromY` and drag to `toY`, at screen `x`; `toY` above `fromY` moves the content up.
        case drag(x: Double, fromY: Double, toY: Double)
        /// The drags are spent, or the list will not move.
        ///
        /// Only ``Loop`` returns it; it means one drag moved nothing after the slop was doubled.
        case ended
    }
}
