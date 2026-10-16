//
// Copyright © Agulhas Labs
//

import Foundation

/// Whether a capture shows the location its state set: some text in the tree holds a number that rounds to the latitude and one that rounds to the longitude.
///
/// **Positive evidence only.** A coordinate on screen proves the simulated location reached the app; its absence proves nothing — most screens never show one, and an app may format it in a locale's own decimal mark — so a capture that does not show it is recorded as set and unverified, never refused. A number counts only at the precision it was printed to (half a unit in its last decimal place), and a whole number never counts, since `52` would match any latitude between 51.5 and 52.5.
public struct LocationShownCheck {
    public static func isShown(_ location: Walkbook.Location, in tree: AXNode) -> Bool {
        let numbers = tree.flattened.flatMap { node in [node.label, node.value].compactMap(\.self).flatMap(decimals(in:)) }
        return numbers.contains { $0.matches(location.latitude) } && numbers.contains { $0.matches(location.longitude) }
    }

    /// Every signed decimal number written with at least one decimal place in `text`, with the precision it was written to.
    static func decimals(in text: String) -> [Printed] {
        text.matches(of: /-?\d+\.(\d+)/).compactMap { match in
            Double(match.output.0).map { Printed(value: $0, places: match.output.1.count) }
        }
    }
}

extension LocationShownCheck {
    /// A number as printed, and how many decimal places it was printed to.
    struct Printed {
        let value: Double
        let places: Int

        /// Whether `coordinate` rounds to this number at the precision it was printed to.
        func matches(_ coordinate: Double) -> Bool {
            abs(value - coordinate) <= 0.5 * pow(10, -Double(places)) + 1e-9
        }
    }
}
