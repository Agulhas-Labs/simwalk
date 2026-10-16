//
// Copyright © Agulhas Labs
//

import Foundation

/// A text's shape: the text with every number written `{n}`, so that two captures differing only in figures, dates and times read alike.
///
/// **A number is what a walkbook's `{n}` stands for** (`RouteTarget.number`): digits in any script, optionally signed, grouped or broken by `.` or `,` — so `+0.29 km` and `−0.05 km` share `{n} km`, and `19:49–20:02` reads `{n}:{n}–{n}:{n}`. A month or a weekday is a word and stays one: a key built from a date's name changes with the date, which is why a heading carrying data is a stated weakness of ``AXSegmenter`` rather than something the shape hides.
public struct TextShape {
    /// `text` with every number in it replaced by `{n}`.
    public static func of(_ text: String) -> String {
        text.replacing(RouteTarget.number, with: RouteTarget.placeholder)
    }

    /// Whether `text` holds a number at all.
    public static func hasNumber(_ text: String) -> Bool {
        text.contains(RouteTarget.number)
    }
}
