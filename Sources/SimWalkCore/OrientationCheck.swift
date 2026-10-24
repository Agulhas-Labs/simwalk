//
// Copyright © Agulhas Labs
//

import Foundation

/// Which orientation a capture's accessibility tree says the app was in, read from its root frame (SimWalk#199).
///
/// **The root frame is in the interface orientation.** A capture's tree is rooted at the app element, and measured on an iPad simulator that element's frame turns with the interface (#149): a landscape app's root is wider than tall, a portrait one's taller than wide. So the frame says what the app actually laid out in, which is what a state is held to — never the `XCUIDevice` call that asked for it, which a portrait-only app answers by staying where it is.
///
/// **What it cannot see, stated rather than passed:** a square root frame is neither, and an empty one is an app element with nothing laid out; both are `nil`, which the manifest records as the axis set and unverified.
///
/// One judgement for every caller: `StateApplicationCheck` holds a walk's captures to it, and a live session's launch fails its start with the same sentence rather than hand an agent a portrait app under a landscape state.
public struct OrientationCheck {
    /// The orientation `frame` shows: `.landscape` when it is wider than tall, `.portrait` when it is taller than wide, and `nil` when it is square or has no area.
    public static func judged(_ frame: AXNode.Frame) -> Walkbook.Orientation? {
        guard frame.width > 0, frame.height > 0, frame.width != frame.height else { return nil }
        return frame.width > frame.height ? .landscape : .portrait
    }

    /// Why a capture whose root frame is `frame` was not taken in `stated`, as a clause a caller prefixes with the state's slug — `asked for landscape and the app kept a 402×874 pt frame (portrait)` — or `nil` when the frame shows `stated` or cannot judge it.
    ///
    /// Names the frame the app kept, so an author reading the refusal sees the evidence rather than a verdict: a portrait-only app asked for landscape keeps its portrait size.
    public static func refusal(stated: Walkbook.Orientation, frame: AXNode.Frame) -> String? {
        guard let shown = judged(frame), shown != stated else { return nil }
        return "asked for \(stated.rawValue) and the app kept a \(TapPointPlacement.size(frame)) pt frame (\(shown.rawValue))"
    }
}
