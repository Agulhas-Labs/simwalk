//
// Copyright © Agulhas Labs
//

import CryptoKit
import Foundation

/// Which screen a hierarchy is, reduced to a value two reads can be compared by.
///
/// **This is what makes a navigating step's arrival checkable.** A `tap` that pushes a detail view returns the instant the touch is delivered, long before the push has happened — and the screen it left then holds perfectly still, so the settle window closes on it and its screenshot is filed under the *target* screen's id with outcome `captured`. Nothing in the bundle can tell that from a real capture: the manifest says the screen was reached and the picture is of somewhere else (SimWalk#6). The honest post-condition of a navigating step is that the hierarchy has *left* the screen it was on, and this is the value that answers it.
///
/// **A timing assumption is exactly what it avoids.** Raising the settle window would paper over the same defect at three times the cost of every walk, and a slow machine would defeat it again; "the identity changed" carries no assumption about how long anything takes.
///
/// **Structure, deliberately, and not the traits a highlight flips.** `isSelected`, `isEnabled` and `value` are left out because a row that lights up under a finger, a pill that becomes the active segment, or a counter that ticks are all changes *within* a screen — and a guard they satisfied would pass on the very list this exists to refuse. Frames are left out for the same reason in the other direction: a screen that jitters or bounces has not become another screen. What is left is what is on the screen and how it nests, which is the thing that cannot survive a push.
///
/// **A collision fails safe.** Two different screens reducing to one digest would report a navigating step as not having landed — an UNREACHABLE verdict naming the step, which is arguable and visible. The reverse, a changed digest for an unchanged screen, is what would file false evidence, and nothing here can produce it: the digest is a pure function of the tree.
public struct ScreenIdentity: Equatable, Sendable {
    /// The hex SHA-256 of the hierarchy's structural description.
    public let digest: String

    /// The identity of the screen this tree is of.
    public static func of(_ tree: AXNode) -> ScreenIdentity {
        let hashed = SHA256.hash(data: Data(description(of: tree).utf8))
        return ScreenIdentity(digest: hashed.map { String(format: "%02x", $0) }.joined())
    }

    /// Whether the hierarchy has moved off the screen this identity was taken from.
    ///
    /// The question a route step asks after it taps: not "is this the screen I wanted" — no walkbook states that, and a label is a string until the walk runs — but "is this still the screen I was on", which a runner can answer without knowing anything about the app.
    public func hasBeenLeft(by tree: AXNode) -> Bool {
        Self.of(tree) != self
    }

    /// The hierarchy written as text: each node's type, label and identifier, and the nesting they sit in.
    ///
    /// The parentheses are load-bearing rather than decoration — without them a child moving out to become a sibling would describe identically, and a re-parented subtree is one of the few structural changes a push routinely makes.
    private static func description(of node: AXNode) -> String {
        var text = "\(node.type)|\(node.label ?? "")|\(node.identifier ?? "")("
        for child in node.children {
            text += description(of: child)
        }
        return text + ")"
    }
}
