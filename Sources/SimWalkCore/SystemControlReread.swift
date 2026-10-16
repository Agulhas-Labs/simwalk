//
// Copyright © Agulhas Labs
//

import Foundation

/// Whether a system sheet's control, read again after the live reads a tap needs, is still the control its first read found (SimWalk#51, item 1).
///
/// **An element bound by index is found again on every read.** `systemTap` takes each match's snapshot, then asks the live element whether it exists, where it is and whether a tap would land on it — each a lookup of its own, by index. While a sheet's table decelerates, HealthKit's rows turn from bare text into `Button`s and the matching set reorders, so the live frame can belong to a different element than the snapshot the scope judged, and the tap lands on a control the scope never approved. So the element is read a second time after the live reads, and only a second read of the same control — its type, identifier, label and box, and still enabled — lets the tap go ahead. One that has gone (`nil`: its snapshot could not be taken) or turned into anything else is passed over.
///
/// **In the core, not the runner, because nothing in `Runner/` is exercised by `swift test`**: the runner keeps the reads and asks here whether they agree, the shape `SettleTracker` set.
public struct SystemControlReread {
    /// Whether `second` is the control `first` was, read either side of the live reads.
    ///
    /// Boxes agree within half a point, the tolerance the runner already uses to match a live frame to a recorded one; a box that moved further is a row sliding under the reads, never passed as the same control.
    static func confirms(_ second: AXNode?, as first: AXNode) -> Bool {
        guard let second, second.isEnabled else { return false }
        return second.type == first.type
            && second.identifier == first.identifier
            && second.label == first.label
            && abs(second.frame.x - first.frame.x) < 0.5
            && abs(second.frame.y - first.frame.y) < 0.5
            && abs(second.frame.width - first.frame.width) < 0.5
            && abs(second.frame.height - first.frame.height) < 0.5
    }
}

public extension SystemControlReread {
    /// The first of `matches` a tap would land on and `accepts` takes, `Button`s before any other kind (a button's own text carries its label too), each candidate read in the one order that makes its live reads its own (SimWalk#51 item 1, #55).
    ///
    /// **Each candidate in turn: its snapshot, its live reads, its snapshot again**, and only a second read `confirms` is the same control is offered to `accepts`. Hittability and the live frame have no snapshot form, so `live` reads them — `nil` where the element has gone or is not hittable — and a set that reordered in that gap would give a live frame of another element than the node judged. The sequence is here rather than in the runner so a test replays it against scripted reads: before, dropping the second read, or the check on it, left `swift test` green (SimWalk#55).
    ///
    /// - Parameters:
    ///   - matches: The live elements matching the step's label, in tree order.
    ///   - snapshot: An element's own snapshot as a node, `nil` where it cannot be taken.
    ///   - live: An element's live reads, `nil` where it has gone or is not hittable.
    ///   - accepts: Whether the caller takes a confirmed node.
    static func firstTappable<Element, Live>(
        among matches: [Element],
        snapshot: (Element) -> AXNode?,
        live: (Element) -> Live?,
        where accepts: (AXNode) -> Bool = { _ in true }
    ) -> Tappable<Live>? {
        for buttons in [true, false] {
            for element in matches {
                guard let first = snapshot(element), first.isEnabled, (first.type == "Button") == buttons, let read = live(element) else { continue }
                guard confirms(snapshot(element), as: first), accepts(first) else { continue }
                return Tappable(node: first, live: read)
            }
        }
        return nil
    }

    /// A control `firstTappable` found: the node its first snapshot read, and the live reads taken between that and the second.
    struct Tappable<Live> {
        /// The control as its first snapshot read it, in the space `accepts` compared it against the tree in.
        public let node: AXNode
        /// Its live reads, which place the tap.
        public let live: Live
    }
}
