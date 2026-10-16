//
// Copyright © Agulhas Labs
//

import Foundation

/// One figure in one captured state, and what checking it against the oracle found — one line of output each (Brief §2.3).
///
/// A field round's headline reads `today/light steps-today: 2,703 matches rolling24h (exact) — midnight 3326, rolling24h 2703 count`: the figure, the window it tracks, and the one it was expected to track, in one line.
public struct FigureCheck: Equatable, Sendable {
    public let screenID: String
    public let stateSlug: String
    public let figureID: String
    public let outcome: Outcome

    public init(screenID: String, stateSlug: String, figureID: String, outcome: Outcome) {
        self.screenID = screenID
        self.stateSlug = stateSlug
        self.figureID = figureID
        self.outcome = outcome
    }

    /// The check as one line.
    public var rendered: String {
        "\(screenID)/\(stateSlug) \(figureID): \(outcome.rendered)"
    }
}

public extension FigureCheck {
    /// One expected value: the window it was computed under, and the value.
    struct WindowValue: Equatable, Sendable {
        public let window: String
        public let value: Double

        public init(window: String, value: Double) {
            self.window = window
            self.value = value
        }
    }

    /// What one figure's check found.
    enum Outcome: Equatable, Sendable {
        /// The figure equals the oracle's value under each of `windows` (at least one), within the figure's printed precision.
        case matches(windows: [String], figure: OnScreenFigure, expected: [WindowValue], unit: String?, attribution: String?)
        /// The figure equals no window's value; every one is listed beside it.
        case matchesNone(figure: OnScreenFigure, expected: [WindowValue], unit: String?, attribution: String?)
        /// Nothing in the capture carries the figure's element.
        case notOnScreen(element: String)
        /// Something carries the element, but not one readable number.
        case unreadable(reason: String)
        /// The oracle gave no usable answer; never a match or a mismatch.
        case oracleFailed(reason: String)

        /// The figure against every window the oracle was asked for, under the figure's stated tolerance.
        static func matching(_ figure: OnScreenFigure, windows: [String], answer: OracleAnswer) -> Outcome {
            guard case let .reply(values, unit, attribution) = answer else {
                if case let .failed(reason) = answer {
                    return .oracleFailed(reason: reason)
                }
                return .oracleFailed(reason: "no answer")
            }
            let missing = windows.filter { values[$0] == nil }
            guard missing.isEmpty else {
                return .oracleFailed(reason: "its reply has no value for window \(missing.map { "'\($0)'" }.joined(separator: ", "))")
            }
            let expected = windows.compactMap { window in values[window].map { WindowValue(window: window, value: $0) } }
            let matched = expected.filter { figure.matches($0.value) }.map(\.window)
            return matched.isEmpty
                ? .matchesNone(figure: figure, expected: expected, unit: unit, attribution: attribution)
                : .matches(windows: matched, figure: figure, expected: expected, unit: unit, attribution: attribution)
        }

        var rendered: String {
            switch self {
            case let .matches(windows, figure, expected, unit, attribution):
                let tolerance = figure.fractionDigits == 0 ? "exact" : "±\(Self.number(figure.tolerance))"
                return "\(figure.rendered) matches \(windows.joined(separator: ", ")) (\(tolerance)) — \(Self.values(expected, unit: unit))\(Self.source(attribution))"
            case let .matchesNone(figure, expected, unit, attribution):
                return "\(figure.rendered) matches none — \(Self.values(expected, unit: unit))\(Self.source(attribution))"
            case let .notOnScreen(element):
                return "not on screen — nothing carries '\(element)' as an identifier or a label"
            case let .unreadable(reason):
                return "no figure — \(reason)"
            case let .oracleFailed(reason):
                return "oracle failed — \(reason)"
            }
        }

        private static func values(_ expected: [WindowValue], unit: String?) -> String {
            expected.map { "\($0.window) \(number($0.value))" }.joined(separator: ", ") + (unit.map { " \($0)" } ?? "")
        }

        private static func source(_ attribution: String?) -> String {
            attribution.map { " — \($0)" } ?? ""
        }

        /// A value as the oracle meant it: `3326`, not `3326.0`.
        private static func number(_ value: Double) -> String {
            value.rounded() == value && abs(value) < 1e15 ? String(Int64(value)) : "\(value)"
        }
    }
}
