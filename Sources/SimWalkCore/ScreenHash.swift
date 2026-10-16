//
// Copyright © Agulhas Labs
//

import CryptoKit
import Foundation

/// A short hash of a screen **as read** — what a live session's answers carry as `screen <hash>`, and what a step's `guard` is compared against before it acts.
///
/// **Everything a reader could see change, and nothing finer.** Each node's type, label, identifier, value, selected and enabled traits and frame — rounded to whole points — in the nesting ``ScreenIdentity`` keeps. ``ScreenIdentity`` asks "is this still the screen I was on" and deliberately ignores values, traits and geometry, since a row lighting up is not a new screen; this asks "is this still exactly what I looked at", where a value ticking or a row moving under the finger is precisely the change a guarded tap must not land on. Sub-point geometry is rounded away because two reads of a still screen can differ in it, and a hash that changed on a screen nobody touched would refuse every guard.
///
/// Printed at ``ShortHash/digits`` hex digits, the length every hash in an answer carries; a collision would pass a guard on a changed screen once in four billion comparisons.
public struct ScreenHash {
    /// The printed hash of `tree`.
    public static func of(_ tree: AXNode) -> String {
        let hashed = SHA256.hash(data: Data(description(of: tree).utf8))
        return ShortHash.of(hashed.map { String(format: "%02x", $0) }.joined())
    }

    /// The tree written as text: each node's visible attributes, each separated so no two different trees write alike, and the nesting in parentheses as ``ScreenIdentity`` writes it.
    private static func description(of node: AXNode) -> String {
        let frame = [node.frame.x, node.frame.y, node.frame.width, node.frame.height].map { String(format: "%.0f", $0) }.joined(separator: ",")
        let fields = [node.type, node.label ?? "", node.identifier ?? "", node.value ?? "", node.isSelected ? "s" : "", node.isEnabled ? "" : "d", frame]
        var text = fields.map(escaped).joined(separator: "|") + "("
        for child in node.children {
            text += description(of: child)
        }
        return text + ")"
    }

    /// `field` with the separators this description uses escaped, so a label holding `|` or `)` cannot write like two fields.
    private static func escaped(_ field: String) -> String {
        field.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }
}
