//
// Copyright © Agulhas Labs
//

import Foundation

/// How long a gesture may run (SimWalk#113, Brief §8 "Gestures are bounded").
///
/// **Bounded so the button is never held down, and the wheel never turned, for minutes between two focus checks.** The guard checks focus before an action and after its last event; whatever is posted in between goes to whatever is frontmost. A refused zero is deliberate too: a scroll of no lines posts nothing and would answer "no visible text changed".
public struct MirrorGestureBounds {
    /// Wheel lines a `scroll` may turn, in either direction (the sign is the direction).
    public static let lines = 1 ... 50
    /// Milliseconds a `swipe` may hold the button.
    public static let milliseconds = 50 ... 5000

    /// `count` when its magnitude is in ``lines``, refused naming the range otherwise.
    public static func checkedLines(_ count: Int) throws(InputRefusal) -> Int32 {
        guard count != Int.min, lines.contains(abs(count)) else {
            throw InputRefusal("lines \(count) is outside 1…\(lines.upperBound) — a scroll turns the wheel 1 to \(lines.upperBound) lines (negative for up or left); zero scrolls nothing")
        }
        return Int32(count)
    }

    /// `ms` when it is in ``milliseconds``, refused naming the range otherwise.
    public static func checkedMilliseconds(_ ms: Int) throws(InputRefusal) -> Int {
        guard milliseconds.contains(ms) else {
            throw InputRefusal("--ms \(ms) is outside \(milliseconds.lowerBound)…\(milliseconds.upperBound) — a drag holds the button for 50 to 5000 milliseconds")
        }
        return ms
    }
}
