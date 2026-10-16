//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// Where a number starts and ends, for a `{n}` pattern and for a lead-in to a label's data: which characters are its digits, and which separators join them into one number rather than ending it.
///
/// Both read the same digit class — a decimal digit in any script — and each is pinned against the characters that are numbers without being digits of a figure.
struct RouteTargetNumberTests {
    /// `{n}`'s digits are decimal digits in any script a number formatter writes — Arabic-Indic, Devanagari, full-width — and never a superscript, a fraction, a circled number or a numeral like `五` or `Ⅻ`, each of which `Character.isNumber` (and so Regex's `.digit`) takes.
    @Test
    func aplaceholderReadsDecimalDigitsInAnyScriptAndNothingElse() {
        let matches = ["Sailing ٢٢", "Sailing ३", "Sailing ３", "Sailing ٣.٤"]
        let misses = ["Sailing ²", "Sailing ½", "Sailing ①", "Sailing 五", "Sailing Ⅻ"]

        for label in matches {
            let tree = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 200), label: label)])
            #expect(RouteTarget.choose(labelled: "Sailing {n}", in: tree) != .none, "'Sailing {n}' should reach '\(label)'")
        }
        for label in misses {
            let tree = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 200), label: label)])
            #expect(RouteTarget.choose(labelled: "Sailing {n}", in: tree) == .none, "'Sailing {n}' should not reach '\(label)'")
        }
    }

    /// Only a `.` or a `,` joins a number's digits: a number grouped by a space, as French draws `4 210` with a narrow non-breaking space, or by an apostrophe, or broken by the Arabic decimal separator, is not one number to `{n}` — and the step finds nothing rather than the number's first half.
    @Test
    func aplaceholderDoesNotReadANumberGroupedBySpacesApostrophesOrArabicSeparators() {
        let misses: [(String, String)] = [
            ("Steps {n}", "Steps 4\u{202F}210"),
            ("Steps {n}", "Steps 4\u{00A0}210"),
            ("Steps {n}", "Steps 4’210"),
            ("{n} km", "٣٫٤ km"),
        ]

        for (step, label) in misses {
            let tree = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 200), label: label)])
            #expect(RouteTarget.choose(labelled: step, in: tree) == .none, "'\(step)' should not reach '\(label)'")
        }
    }

    /// **A group separator between two digits is inside the number**, as a comma is.
    ///
    /// French, Russian and Swedish formatters group digits with a narrow non-breaking, non-breaking or thin space, so under those locales `'Steps 4'` against `Steps 4 210` cuts the figure in half exactly as `'Steps 4'` against `Steps 4,210` does in English — and the replay's own case, `'Steps, Down 756 on the previous day, 2'`, meets `…, 2 300`. After a word the same space still separates it from the figures.
    @Test
    func aleadInDoesNotEndInsideANumberGroupedBySpaces() {
        let misses: [(String, String)] = [
            ("Steps 4", "Steps 4\u{202F}210"),
            ("Steps 4", "Steps 4\u{00A0}210"),
            ("Steps 4", "Steps 4\u{2009}210"),
            ("Steps, Down 756 on the previous day, 2", "Steps, Down 756 on the previous day, 2\u{202F}300"),
        ]

        for (step, label) in misses {
            let tree = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 200), label: label)])
            #expect(RouteTarget.choose(labelled: step, in: tree) == .none, "'\(step)' should not lead into '\(label)'")
        }
        for label in ["Steps 4\u{202F}210", "Steps\u{202F}4\u{202F}210"] {
            let tree = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 200), label: label)])
            #expect(RouteTarget.choose(labelled: "Steps", in: tree) != .none, "'Steps' should lead into '\(label)'")
        }
    }

    /// The digit a lead-in needs is a decimal digit, in any script — not merely something other than a letter, and not a superscript, fraction, circled number or numeral.
    ///
    /// `'Heart Rate'` against `Heart Rate (bpm)` is the case "not a letter" would get wrong: a parenthesis is not data, and the unit it opens is part of the name.
    @Test
    func aleadInNeedsADecimalDigitAfterItsSeparators() {
        let misses: [(String, String)] = [
            ("Heart Rate", "Heart Rate (bpm)"),
            ("Sailing", "Sailing ²"),
            ("Sailing", "Sailing ½"),
            ("Sailing", "Sailing ①"),
            ("Sailing", "Sailing 五"),
            ("Sailing", "Sailing Ⅻ"),
        ]
        let hits: [(String, String)] = [
            ("Sailing", "Sailing ٢٢"),
            ("Sailing", "Sailing ३"),
        ]

        for (step, label) in misses {
            let tree = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 200), label: label)])
            #expect(RouteTarget.choose(labelled: step, in: tree) == .none, "'\(step)' should not lead into '\(label)'")
        }
        for (step, label) in hits {
            let tree = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 200), label: label)])
            guard case let .chosen(target, _) = RouteTarget.choose(labelled: step, in: tree) else {
                Issue.record("'\(step)' should lead into '\(label)'")
                continue
            }
            #expect(target.match == .prefix)
        }
    }

    private static func screen(_ content: [AXNode]) -> AXNode {
        AXNode(type: "Application", frame: frame(y: 0, height: 874), children: [
            AXNode(type: "Window", frame: frame(y: 0, height: 874), children: content),
        ])
    }

    private static func frame(y: Double, height: Double = 60) -> AXNode.Frame {
        AXNode.Frame(x: 0, y: y, width: 402, height: height)
    }
}
