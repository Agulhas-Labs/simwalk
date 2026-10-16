//
// Copyright © Agulhas Labs
//

import Foundation

/// How a window fraction is spelled in a label or an answer: no leading zero, a fixed number of decimals, so `.50,.62` is the same text wherever it is read.
///
/// A caseless namespace, because the action labels and both summaries spell fractions the same way and a second copy is where one of them starts printing `0.5`.
struct MirrorFractionText {
    /// `value` to `decimals` places, its leading zero dropped (`0.512` → `.512`, `1.0` → `1.000`).
    static func spell(_ value: Double, decimals: Int) -> String {
        let text = String(format: "%.\(decimals)f", value)
        return text.hasPrefix("0.") ? String(text.dropFirst()) : text
    }

    /// A point, `x,y`, to `decimals` places.
    static func spell(x: Double, y: Double, decimals: Int) -> String {
        "\(spell(x, decimals: decimals)),\(spell(y, decimals: decimals))"
    }
}
