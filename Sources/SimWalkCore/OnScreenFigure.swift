//
// Copyright © Agulhas Labs
//

import Foundation

/// A number as a screen printed it: the text it was read from, its value, how many decimal places it was printed to, and the unit text written after it.
public struct OnScreenFigure: Equatable, Sendable {
    /// The number exactly as drawn — `2,703`, `4,2` — for a reader to set beside the value it was read as.
    public let printed: String
    /// The value, read under the capture's locale.
    public let value: Double
    /// The decimal places printed, which is the precision a match is held to.
    public let fractionDigits: Int
    /// The text following the number up to the next comma or middle dot (`steps`, `km`, `%`); `nil` when nothing follows.
    public let unit: String?

    public init(printed: String, value: Double, fractionDigits: Int, unit: String?) {
        self.printed = printed
        self.value = value
        self.fractionDigits = fractionDigits
        self.unit = unit
    }

    /// Half a unit in the last printed place: an expected value within it rounds to what was printed, whichever rounding the app used.
    ///
    /// **Exact for integers**: two integers within ±0.5 of each other are equal, so a count is matched exactly; a prorated rolling sum of `2703.4` still matches a printed `2,703`, which is the figure it would draw.
    public var tolerance: Double {
        0.5 / pow(10, Double(fractionDigits))
    }

    /// Whether `expected` is what this figure would print as.
    public func matches(_ expected: Double) -> Bool {
        abs(expected - value) <= tolerance * (1 + 1e-9)
    }

    /// The figure and its unit as the screen drew them.
    var rendered: String {
        unit.map { "\(printed) \($0)" } ?? printed
    }
}
