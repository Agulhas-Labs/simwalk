//
// Copyright © Agulhas Labs
//

import Foundation

/// Whether `systemTap`'s drags down a sheet's scroll container go on, from what one read of the step's label found (SimWalk#59).
///
/// **The drags bring a control on screen; they never admit it.** A read that finds an enabled match a tap would land on stops them, whether or not the match has stopped moving: admitting and tapping stay with the step's own poll, which waits between reads and holds the control to every check — `SystemSheetScope.admits`, `SystemControlReread`'s two reads, the #39/#47/#51 guards. Measured on HealthKit's sheet, iOS 27.0: `Allow`, the last row, was enabled and hittable from the first drag, but the list was still bouncing, so the two reads `SystemControlReread.firstTappable` takes read its box at y 566.67 then 580.00 and rightly refused it; the next drag followed about 0.1 s later, the list never settled, and all twelve drags were spent — about 18 s — before the poll tapped it.
///
/// **In the core, not the runner**, because nothing in `Runner/` is exercised by `swift test`: the runner keeps the reads and asks here whether to drag again, the shape `SettleTracker` set.
public struct SystemTapScroll {
    /// Whether to drag again: `true` until one of `matches` reads enabled in its snapshot and hittable live.
    ///
    /// **One read of each match, never two**: a match is judged by its first snapshot alone, so a box still sliding under the reads counts as found. A match whose snapshot cannot be taken, reads disabled, or would not take a tap is not in reach, and the drags go on.
    ///
    /// - Parameters:
    ///   - matches: The live elements matching the step's label, in tree order.
    ///   - snapshot: An element's own snapshot as a node, `nil` where it cannot be taken.
    ///   - hittable: Whether a tap on the element would land on it; `false` where it has gone.
    public static func keepsDragging<Element>(
        over matches: [Element],
        snapshot: (Element) -> AXNode?,
        hittable: (Element) -> Bool
    ) -> Bool {
        !matches.contains { element in
            guard let node = snapshot(element), node.isEnabled else { return false }
            return hittable(element)
        }
    }
}
