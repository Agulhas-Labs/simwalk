//
// Copyright © Agulhas Labs
//

import Foundation

/// Takes out of a tree the elements of table cells UIKit has not laid out (SimWalk#230).
///
/// A table builds the cells below the fold lazily: such a cell's frame is already where it will scroll to, wholly outside the screen, but its labels and controls still sit at a placeholder frame (a settings table's switches all at `0,142 63×28`, nowhere near their cell) and its labels are filled only when the cell is laid out. VoiceOver scrolls a cell on screen before reading it, so what the snapshot says of those elements is not what a user meets.
///
/// **Both conditions.** An element is taken out when its nearest `Cell` ancestor has an area and lies wholly off the screen, **and** the element's own frame is not within that cell's frame (a point of slack). An element of an off-screen cell whose frame is inside its cell was laid out, and is still judged.
struct CellsNotLaidOut {
    /// How far an element may stray outside its cell's frame and still count as inside it, in points.
    private static let tolerance = 1.0

    /// The tree less every element of a cell not laid out, and what is under it.
    static func removed(from tree: AXNode) -> AXNode {
        prune(tree, screen: tree.screenBounds, cell: nil)
    }

    private static func prune(_ node: AXNode, screen: AXNode.Frame, cell: AXNode.Frame?) -> AXNode {
        var kept = node
        let childCell = node.type == "Cell" ? offScreenFrame(of: node, screen: screen) : cell
        kept.children = node.children.compactMap { child in
            if let cell = childCell, !cell.contains(child.frame, tolerance: tolerance) {
                return nil
            }
            return prune(child, screen: screen, cell: childCell)
        }
        return kept
    }

    /// The cell's frame when it lies wholly off the screen; `nil` for a cell on screen, or one with no area (not laid out at all, so nothing to compare with).
    private static func offScreenFrame(of cell: AXNode, screen: AXNode.Frame) -> AXNode.Frame? {
        cell.frame.hasArea && !cell.frame.isOnScreen(screen) ? cell.frame : nil
    }
}
