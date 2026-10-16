//
// Copyright © Agulhas Labs
//

import Foundation

/// One line of text recognised in a capture of the mirrored phone, with where it sits in the window.
///
/// **The box is in window fractions, origin top-left, because that is the one frame that survives.** A capture's pixel size changes with the window's size and the display's scale, and Vision answers in a bottom-left origin; a line placed as a fraction of the window is comparable between two reads, and is what a later tap is aimed with. The text is whatever the recogniser drew, uncorrected, so a figure such as `1,122` is served as it appears.
public struct MirrorTextLine: Equatable, Sendable, Codable {
    /// The recognised text, as drawn.
    public let text: String
    /// The box centre's horizontal position, 0 (left edge) to 1 (right edge) of the window.
    public let centreX: Double
    /// The box centre's vertical position, 0 (top edge) to 1 (bottom edge) of the window.
    public let centreY: Double
    /// The box width as a fraction of the window's width.
    public let width: Double
    /// The box height as a fraction of the window's height.
    public let height: Double
    /// The recogniser's confidence in the text, 0 to 1.
    public let confidence: Double

    public init(text: String, centreX: Double, centreY: Double, width: Double, height: Double, confidence: Double) {
        self.text = text
        self.centreX = centreX
        self.centreY = centreY
        self.width = width
        self.height = height
        self.confidence = confidence
    }
}

extension MirrorTextLine {
    /// The confidence below which a line takes no part in a comparison.
    ///
    /// **Measured live on 2026-10-14**: Vision's accurate mode answers in coarse steps (0.3, 0.5, 1.0), and every line of glyph soup read inside an app icon (`• aall`, `••0•00`, `-•N`, `a Kidon`) came back at 0.3 and came and went between reads of the same still screen. Anything at 0.5 or above was stable. Brief open question 1 is about where this sits.
    static let comparisonConfidenceFloor = 0.5

    /// The characters Vision draws or invents between words and drops again on the next read of the same screen: bullets, middle dots and the replacement characters.
    private static let separators: Set<Character> = ["•", "·", "∙", "‧", "⋅", "●", "◦", "▪", "\u{FFFE}", "\u{FFFD}"]

    /// Whether the recogniser was sure enough of this line for a comparison to rest on it.
    var isComparable: Bool {
        confidence >= Self.comparisonConfidenceFloor
    }

    /// The text with case, whitespace and separator glyphs taken out.
    ///
    /// It is what two reads of one line agree on, though Vision draws `Is down 3.` and `is down 3.`, or `1 0ct.` and `10ct.`, differently from one read to the next. The served text is never replaced by it.
    var comparisonKey: String {
        String(text.lowercased().filter { !$0.isWhitespace && !Self.separators.contains($0) })
    }

    /// The characters a counter or a delta changes by: a different one of these before the same tail is a real change (`+3.2%` to `-3.2%`, `↑ 2.5 kg` to `↓ 2.5 kg`).
    private static let signs: Set<Character> = ["+", "-", "−", "↑", "↓", "←", "→", "▲", "▼"]

    /// The first character of the served text, past any leading whitespace and separator glyphs, when it stands alone before a word.
    ///
    /// That is: followed by whitespace, then a letter. `nil` for any other shape, such as a sign fused to its figure (`+3.2%`) or a lead with no word after it.
    private var leadingGlyph: Character? {
        let trimmed = text.drop { $0.isWhitespace || Self.separators.contains($0) }
        guard let first = trimmed.first else {
            return nil
        }
        let rest = trimmed.dropFirst()
        guard rest.first?.isWhitespace == true, rest.drop(while: \.isWhitespace).first?.isLetter == true else {
            return nil
        }
        return first
    }

    /// Whether `other` is the same line of text for comparison.
    ///
    /// Keys are equal, or differ only in the first character with at least four characters after it, and only when that character is a separate glyph before a word in both served texts: `J Declining`, `1 Declining` and `↓ Declining` are one line, the icon drawn differently on each read. A difference in a digit or a sign is never forgiven, even in that shape, because it is the content: `2 Selected` to `3 Selected`, `5 min ago` to `6 min ago`, `+3.2%` to `-3.2%` and `↑ 2.5 kg` to `↓ 2.5 kg` are real changes a step must report, and a countdown must not settle early on one. A difference anywhere else, a single digit included (`34min` against `35min`), is a real change too.
    func isSameText(as other: MirrorTextLine) -> Bool {
        let mine = comparisonKey
        let theirs = other.comparisonKey
        if mine == theirs {
            return true
        }
        guard mine.count == theirs.count, mine.count >= 5, mine.dropFirst() == theirs.dropFirst(),
              let myGlyph = leadingGlyph, let theirGlyph = other.leadingGlyph
        else {
            return false
        }
        let bothDigits = myGlyph.isNumber && theirGlyph.isNumber
        let bothSigns = Self.signs.contains(myGlyph) && Self.signs.contains(theirGlyph)
        return !bothDigits && !bothSigns
    }
}
