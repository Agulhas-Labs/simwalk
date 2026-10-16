//
// Copyright © Agulhas Labs
//

import Foundation

/// Finds a figure's element in a captured tree and reads its number under the capture's locale (Brief §2.3).
///
/// The element is looked for by **accessibility identifier first**, then by label: whole, or as a pattern whose one `{n}` (`RouteTarget.placeholder`) stands for the figure. An identified or whole-label element is read from its value, else its label — the first of the two that carries a digit — and that text must hold exactly one number. Several elements matching is fine while they read alike (a cell and its text); reading differently, it is `unreadable`, never the first.
///
/// **Separators are the locale's.** `2,703` is two thousand seven hundred and three in `en_US` and not a number `de_DE` writes; `4,2` is four point two in `de_DE`. A grouped number whose groups a formatter would not draw (`3,43` in `en_US`) is refused rather than read as `343`. Where the locale groups with a space, the non-breaking, narrow non-breaking and thin spaces are all taken, as `RouteTarget` takes them.
public struct FigureScraper {
    /// The figure's reading in `tree`, under `locale`.
    public static func reading(of figure: Walkbook.Figure, in tree: AXNode, locale: Locale) -> FigureReading {
        let nodes = tree.flattened
        var readings = nodes.filter { $0.identifier == figure.element }.map { read($0, locale: locale) }
        if readings.isEmpty {
            if figure.element.contains(RouteTarget.placeholder) {
                readings = nodes.compactMap { readPattern(figure.element, in: $0, locale: locale) }
            } else {
                readings = nodes.filter { $0.label == figure.element }.map { read($0, locale: locale) }
            }
        }
        guard let first = readings.first else { return .notOnScreen }
        var figures: [OnScreenFigure] = []
        for case let .read(figure) in readings where !figures.contains(where: { $0.value == figure.value && $0.fractionDigits == figure.fractionDigits }) {
            figures.append(figure)
        }
        return switch figures.count {
        case 0:
            first
        case 1:
            .read(figures[0])
        default:
            .unreadable(reason: "\(figures.count) elements match '\(figure.element)', reading \(figures.map(\.printed).joined(separator: ", "))")
        }
    }

    /// An identified or whole-label element's number: from its value, else its label — the first of the two carrying a digit.
    private static func read(_ node: AXNode, locale: Locale) -> FigureReading {
        let texts = [node.value, node.label].compactMap(\.self).filter { !$0.isEmpty }
        guard let text = texts.first(where: { $0.contains(where: isDecimalDigit) }) else {
            let shown = texts.first.map { "'\($0)'" } ?? "an element with no label or value"
            return .unreadable(reason: "\(shown) carries no number")
        }
        return reading(of: text, locale: locale)
    }

    /// A label's number where `pattern` names it with `{n}`, `.unreadable` where the label holds a placeholder there, and `nil` when the label is not the pattern's literal text around one number or a placeholder.
    private static func readPattern(_ pattern: String, in node: AXNode, locale: Locale) -> FigureReading? {
        let literals = pattern.components(separatedBy: RouteTarget.placeholder)
        guard literals.count == 2, let label = node.label, label.count >= pattern.count - RouteTarget.placeholder.count,
              label.hasPrefix(literals[0]), label.hasSuffix(literals[1]) else { return nil }
        let middle = String(label.dropFirst(literals[0].count).dropLast(literals[1].count))
        let tokens = numberTokens(in: middle, locale: locale)
        // The element is there, showing a placeholder where the figure goes (`Steps: —`): no figure, not no element.
        // A pattern that is only `{n}` has no literal to say the label is the element, so it claims nothing; nor does a
        // middle with letters in it, which is other text sharing a literal (`Daily steps` against `{n} steps`).
        if tokens.isEmpty, !(literals[0].isEmpty && literals[1].isEmpty), !middle.contains(where: \.isLetter) {
            return .unreadable(reason: "'\(label)' carries no number")
        }
        guard tokens.count == 1, let token = tokens.first, middle[token.range].count == middle.trimmingCharacters(in: .whitespaces).count else { return nil }
        return figure(from: middle, token: token, trailing: literals[1], locale: locale)
    }

    /// The one number `text` holds, or why it holds none or several.
    static func reading(of text: String, locale: Locale) -> FigureReading {
        let tokens = numberTokens(in: text, locale: locale)
        guard tokens.count == 1, let token = tokens.first else {
            return .unreadable(reason: tokens.isEmpty ? "'\(text)' carries no number" : "'\(text)' carries \(tokens.count) numbers")
        }
        return figure(from: text, token: token, trailing: String(text[token.range.upperBound...]), locale: locale)
    }

    /// The figure one token is, its unit read from `trailing`.
    private static func figure(from text: String, token: Token, trailing: String, locale: Locale) -> FigureReading {
        guard let value = token.value else {
            return .unreadable(reason: "'\(text[token.range])' is not a number as \(locale.identifier) writes one")
        }
        let unit = trailing.prefix { $0 != "," && $0 != "·" && $0 != "\n" }.trimmingCharacters(in: .whitespaces)
        return .read(OnScreenFigure(printed: String(text[token.range]), value: value, fractionDigits: token.fractionDigits, unit: unit.isEmpty ? nil : unit))
    }

    /// Every run of digits in `text` joined by the locale's own separators, with a sign directly before it that no word or digit precedes.
    static func numberTokens(in text: String, locale: Locale) -> [Token] {
        let separators = Separators(locale)
        var tokens: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard isDecimalDigit(text[index]) else {
                index = text.index(after: index)
                continue
            }
            var start = index
            if start > text.startIndex {
                let before = text.index(before: start)
                let beforeSign = before > text.startIndex ? text[text.index(before: before)] : " "
                if "+-−".contains(text[before]), !beforeSign.isLetter, !isDecimalDigit(beforeSign) {
                    start = before
                }
            }
            var end = text.index(after: index)
            while end < text.endIndex {
                let character = text[end]
                let next = text.index(after: end)
                if isDecimalDigit(character) {
                    end = next
                } else if separators.joins(character), next < text.endIndex, isDecimalDigit(text[next]) {
                    end = next
                } else {
                    break
                }
            }
            tokens.append(Token(text: text[start ..< end], range: start ..< end, separators: separators))
            index = end
        }
        return tokens
    }

    /// A decimal digit in any script, read as `RouteTarget` reads one: by its first scalar's numeric type.
    private static func isDecimalDigit(_ character: Character) -> Bool {
        character.unicodeScalars.first?.properties.numericType == .decimal
    }
}

extension FigureScraper {
    /// The two separators a locale writes a number with.
    struct Separators {
        let decimal: Character
        let grouping: Set<Character>
        /// Whether the locale groups its inner digits in twos (an Indian lakh grouping: `1,23,456`), as `NumberFormatter.secondaryGroupingSize` says.
        let groupsInTwos: Bool

        init(_ locale: Locale) {
            decimal = locale.decimalSeparator?.first ?? "."
            var grouping = Set(locale.groupingSeparator ?? "")
            // A locale that groups with a space is drawn with any of the three a formatter uses.
            if grouping.contains(where: \.isWhitespace) {
                grouping.formUnion(["\u{00A0}", "\u{202F}", "\u{2009}"])
            }
            self.grouping = grouping
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            groupsInTwos = formatter.secondaryGroupingSize == 2
        }

        /// Whether `character` may sit between two digits of one number.
        func joins(_ character: Character) -> Bool {
            character == decimal || grouping.contains(character)
        }
    }

    /// One number as written, and its value under the locale that wrote it.
    struct Token {
        let range: Range<String.Index>
        /// `nil` where the separators are not in a shape the locale draws: two decimal separators, grouping after the decimal, or groups a formatter would not make.
        let value: Double?
        let fractionDigits: Int

        init(text: Substring, range: Range<String.Index>, separators: Separators) {
            self.range = range
            var normalised = ""
            var integerGroups = [0]
            var fraction: Int?
            var wellFormed = true
            for character in text {
                if let digit = character.wholeNumberValue, character.unicodeScalars.first?.properties.numericType == .decimal {
                    normalised += String(digit)
                    if let digits = fraction {
                        fraction = digits + 1
                    } else {
                        integerGroups[integerGroups.count - 1] += 1
                    }
                } else if character == separators.decimal, fraction == nil {
                    normalised += "."
                    fraction = 0
                } else if separators.grouping.contains(character), fraction == nil {
                    integerGroups.append(0)
                } else if "+-−".contains(character), normalised.isEmpty {
                    normalised += character == "+" ? "" : "-"
                } else {
                    wellFormed = false
                }
            }
            // Grouped as a formatter groups: a lead of one to three digits, then groups of three, the last of three.
            // Inside a locale that groups in twos the lakh pattern is the only one: a lead of one or two digits,
            // every inner group of two, the last of three (`12,34,56,789`, never `1,234,56,789`).
            if integerGroups.count > 1 {
                let inner = integerGroups.dropFirst().dropLast()
                let lead = integerGroups[0]
                if separators.groupsInTwos {
                    wellFormed = wellFormed && (1 ... 2).contains(lead) && integerGroups.last == 3 && inner.allSatisfy { $0 == 2 }
                } else {
                    wellFormed = wellFormed && (1 ... 3).contains(lead) && integerGroups.last == 3 && inner.allSatisfy { $0 == 3 }
                }
            }
            value = wellFormed ? Double(normalised) : nil
            fractionDigits = fraction ?? 0
        }
    }
}
