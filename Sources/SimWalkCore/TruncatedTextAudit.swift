//
// Copyright © Agulhas Labs
//

import Foundation

/// Finds text drawn cut short: a `StaticText` labelled `Notifications` that the screenshot shows as `Notific…`, a `Controls` button drawn `Contr` over `ols`, or a line drawn `Pre vi…` that no element carries.
///
/// **Why SimWalk has its own rule.** Apple's `textClipped` is not reliable for this: on a specimen whose titles read `Notific…` and `Langu…` at an accessibility size it flagged one of the two, flagged that one again where it is whole, and fired issues with no element on a clean screen. The tree cannot say either, because the label is the full string whatever is drawn. The only evidence is the pixels.
///
/// **What it does.** One recognition per capture, never per element. For each `StaticText`, `Button` and `Link` with a label whose frame lies wholly on screen, the recognised lines whose box centre falls inside the frame are joined in reading order with single spaces. It is a finding when that text ends in `…` or `...`, has something before the ellipsis, and what precedes the ellipsis is a strict prefix of the label (runs of whitespace collapsed on both sides, case-sensitive). Recognition noise cannot fake a prefix followed by an ellipsis, so text that was merely misread is not a finding. It is also a finding when two of those lines, a row apart, break a word: the first's last word joined to the second's first is a word of the label and the first's last word alone is not (a hyphen ends no word in a letter, so hyphenation is not one).
///
/// **Text drawn outside the tree.** A row hidden from accessibility under columns that carry combined labels draws text no element holds. Every recognised line whose centre lies in no text element and outside the keyboard is examined, and the heading counts them; one that ends in an ellipsis with something before it is a finding, `drawn text`, unless an element under its centre has a label, value or placeholder holding the line whole (a combined label that ends `…` itself).
///
/// **What it cannot tell.** Text clipped without an ellipsis, and text clipped inside an element whose label holds the whole of it. A label that is deliberately fuller than the text drawn, such as a `Loading…` placeholder over the label `Loading your library` or a message preview cut by design, reads as truncation at every size, so it says nothing about what a larger type size did. Text drawn in a different case from its label, such as an uppercased section header, is not matched, so it is never a finding.
///
/// **Not every capture is checked.** Without a recogniser the rule examined nothing and its heading says so (never `clean`); a capture whose screenshot is missing or unreadable, or on which recognition failed, is counted as not checked, and the answer says which (and the failure's cause).
public struct TruncatedTextAudit: LabelAuditRule {
    public static let name = AuditRuleName.truncatedText

    public static var findingNoun: String {
        "text run"
    }

    public static var findingClause: String {
        "drawn cut short (an ellipsis, or a word broken across lines)"
    }

    public static var examinedNoun: String {
        "text run"
    }

    public static var examinedAdjective: String {
        "on-screen"
    }

    private let recognizer: (any ScreenTextRecognizing)?

    public init(recognizer: (any ScreenTextRecognizing)?) {
        self.recognizer = recognizer
    }

    public func notApplicableReason(over captures: [BundleAuditScope.Capture], result: LabelRuleResult) -> String {
        if recognizer == nil {
            return "no text recognizer on this face, so the rule did not run"
        }
        guard !captures.isEmpty, result.unchecked == captures.count else {
            return "no text runs on any screen"
        }
        if result.recognitionFailed == result.unchecked {
            return "text recognition failed on every capture (\(result.recognitionFailure ?? "no cause given"))"
        }
        return "no capture's screenshot could be read"
    }

    public func evaluate(_ captures: [BundleAuditScope.Capture]) -> LabelRuleResult {
        var result = LabelRuleResult()
        for capture in captures {
            guard let recognizer else {
                continue
            }
            guard let url = capture.screenshotURL, FileManager.default.isReadableFile(atPath: url.path) else {
                result.unchecked += 1
                continue
            }
            let lines: [MirrorTextLine]
            do {
                lines = try recognizer.lines(inPNGAt: url)
            } catch {
                result.unchecked += 1
                result.recognitionFailed += 1
                result.recognitionFailure = result.recognitionFailure ?? Self.cause(of: error)
                continue
            }
            result.absorb(evaluate(capture.tree, lines: lines, screenID: capture.screenID, stateSlug: capture.stateSlug))
        }
        return result
    }

    /// The words for why recognition failed: the error's own cause when it gives one, else its description.
    private static func cause(of error: any Error) -> String {
        (error as? any ScreenTextRecognitionFailure)?.cause ?? String(describing: error)
    }

    /// The rule over one tree and the lines recognised in its screenshot: each text run's lines, then the lines outside every run.
    func evaluate(_ tree: AXNode, lines: [MirrorTextLine], screenID: String, stateSlug: String) -> LabelRuleResult {
        let screen = tree.screenBounds
        let nodes = tree.flattenedLeavingOutKeyboard
        var result = LabelRuleResult()
        result.offScreen = nodes.filter { Self.carriesText($0) && !Self.isTextRun($0, within: screen) }.count
        for run in nodes where Self.isTextRun(run, within: screen) {
            result.examined += 1
            let inside = MirrorRead.readingOrder(lines.filter { Self.centre(of: $0, in: screen, liesIn: run.frame) })
            let label = run.label ?? ""
            let drawn = inside.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.isTruncation(drawn, of: label) {
                result.findings.append(LabelFinding(screenID: screenID, stateSlug: stateSlug, type: run.type, label: run.label, frame: run.frame, note: "reads \"\(drawn)\""))
            } else if let broken = Self.wordBroken(across: inside, of: label) {
                result.findings.append(LabelFinding(screenID: screenID, stateSlug: stateSlug, type: run.type, label: run.label, frame: run.frame, note: "breaks mid-word: \"\(broken)\""))
            }
        }
        // A line inside a text element the rule does not judge (one partly off screen) is the tree's text, not text without an element, so only the keyboard and the text elements of every placing are left out.
        let covered = tree.flattened.filter(ScreenIdentifier.isKeyboard).map(\.frame) + nodes.filter(Self.carriesText).map(\.frame)
        let outside = lines.filter { line in !covered.contains { Self.centre(of: line, in: screen, liesIn: $0) } }
        result.drawnLinesOutside = outside.count
        // With no label to compare against, a misread (a page-dot glyph read as "…" beside a word) is all a low-confidence line can be, so only a line read with confidence is judged.
        for line in outside where line.isComparable && Self.endsCutShort(line.text) {
            let segments = Self.cutShortSegments(of: line)
            for (index, segment) in segments.enumerated() {
                let above = Self.firstLine(above: segments, at: index, of: line, among: outside)
                let text = [above, segment.text].compactMap(\.self).joined(separator: " ")
                let holder = nodes.first { node in
                    Self.centre(of: segment.line, in: screen, liesIn: node.frame) && [node.label, node.value, node.placeholder].contains { Self.holds($0, text) || Self.holds($0, segment.text) }
                }
                guard holder == nil else { continue }
                // An element covering the whole screen (the application, a window) holds every line, and its label is the app's name, which says nothing about where the text is.
                let container = nodes.filter { node in
                    !AuditedControl.isBlank(node.label) && node.frame.hasArea && !Self.covers(node.frame, screen) && Self.centre(of: segment.line, in: screen, liesIn: node.frame)
                }.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
                let whose = container?.label.map { "no accessibility element of its own; inside '\(AuditRowFormat.trim($0))'" } ?? "no accessibility element"
                result.findings.append(LabelFinding(screenID: screenID, stateSlug: stateSlug, type: Self.drawnTextType, label: text, frame: Self.frame(of: segment.line, in: screen), note: "(\(whose)) cut short with an ellipsis"))
            }
        }
        return result
    }

    /// The type a finding about drawn text with no element of its own is given, which its row reads first.
    static var drawnTextType: String {
        "drawn text"
    }

    /// The element types whose label is text the rule judges against what was drawn.
    private static let textTypes: Set<String> = ["StaticText", "Button", "Link"]

    private static func carriesText(_ node: AXNode) -> Bool {
        textTypes.contains(node.type) && !AuditedControl.isBlank(node.label) && node.frame.hasArea
    }

    private static func isTextRun(_ node: AXNode, within screen: AXNode.Frame) -> Bool {
        let frame = node.frame
        return carriesText(node) && frame.minX >= screen.minX && frame.maxX <= screen.maxX && frame.y >= screen.y && frame.maxY <= screen.maxY
    }

    /// Whether `frame` takes in the whole of `screen`.
    private static func covers(_ frame: AXNode.Frame, _ screen: AXNode.Frame) -> Bool {
        frame.minX <= screen.minX && frame.maxX >= screen.maxX && frame.y <= screen.y && frame.maxY >= screen.maxY
    }

    /// Whether `line`'s box centre, mapped from image fractions through the screen's bounds, lies inside `frame`.
    private static func centre(of line: MirrorTextLine, in screen: AXNode.Frame, liesIn frame: AXNode.Frame) -> Bool {
        let x = screen.x + line.centreX * screen.width
        let y = screen.y + line.centreY * screen.height
        return x >= frame.minX && x <= frame.maxX && y >= frame.y && y <= frame.maxY
    }

    /// `line`'s box in the tree's points.
    private static func frame(of line: MirrorTextLine, in screen: AXNode.Frame) -> AXNode.Frame {
        AXNode.Frame(
            x: screen.x + (line.centreX - line.width / 2) * screen.width,
            y: screen.y + (line.centreY - line.height / 2) * screen.height,
            width: line.width * screen.width,
            height: line.height * screen.height
        )
    }

    /// Whether `text` ends in an ellipsis with something other than space before it.
    private static func endsCutShort(_ text: String) -> Bool {
        guard let stem = withoutEllipsis(text) else { return false }
        return !stem.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Whether `text` (an element's label, value or placeholder) holds `line` whole, folded as the comparison folds and with case ignored.
    private static func holds(_ text: String?, _ line: String) -> Bool {
        guard let text else { return false }
        let drawn = folded(line)
        return !drawn.isEmpty && folded(text).contains(drawn)
    }

    /// The two halves of a word of `label` broken across consecutive rows of `lines` (in reading order), as `Contr / ols`; none when no word is.
    ///
    /// A break is a line ending in a letter followed, a row down, by one starting with a letter, where the first's last word joined to the second's first word is a word of the label and the first's last word alone is not; a hyphen at the end of the first line is a hyphenation, which ends in no letter.
    private static func wordBroken(across lines: [MirrorTextLine], of label: String) -> String? {
        let words = Set(folded(label).split(separator: " ").map { trimmedToWord(String($0)) })
        for (upper, lower) in zip(lines, lines.dropFirst()) where abs(lower.centreY - upper.centreY) > min(upper.height, lower.height) / 2 {
            let first = upper.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let second = lower.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard first.last?.isLetter == true, second.first?.isLetter == true,
                  let head = first.split(whereSeparator: \.isWhitespace).last,
                  let tail = second.split(whereSeparator: \.isWhitespace).first else { continue }
            let headWord = trimmedToWord(folded(String(head)))
            if words.contains(headWord + trimmedToWord(folded(String(tail)))), !words.contains(headWord) {
                return "\(head) / \(tail)"
            }
        }
        return nil
    }

    /// `text` folded for comparing words: quotes straightened, whitespace collapsed, lowercased.
    private static func folded(_ text: String) -> String {
        collapsed(straightened(text)).lowercased()
    }

    /// `word` without the punctuation around it (`Controls,` is `Controls`), keeping what is inside it.
    private static func trimmedToWord(_ word: String) -> String {
        word.trimmingCharacters(in: CharacterSet.letters.union(.decimalDigits).inverted)
    }

    /// Whether `drawn` is a strict prefix of `label` followed by an ellipsis.
    static func isTruncation(_ drawn: String, of label: String) -> Bool {
        guard let stem = withoutEllipsis(drawn) else { return false }
        // A label that ends in an ellipsis of its own (`Learn more…`) drawn whole reads the same, so the comparison is against the label without it.
        let full = collapsed(straightened(withoutEllipsis(label) ?? label))
        let head = withoutLeadingBullet(collapsed(straightened(stem)), unless: full)
        return !head.isEmpty && full.count > head.count && full.hasPrefix(head)
    }

    /// `head` without a leading `•` the label does not start with: a row's unread dot drawn beside its title is read into the title's first line (SimWalk#232).
    private static func withoutLeadingBullet(_ head: String, unless full: String) -> String {
        guard head.hasPrefix("•"), !full.hasPrefix("•") else { return head }
        return String(head.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    /// The text before a trailing `…` or `...`, or nothing when it does not end in one.
    private static func withoutEllipsis(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("…") {
            return String(trimmed.dropLast())
        }
        return trimmed.hasSuffix("...") ? String(trimmed.dropLast(3)) : nil
    }

    /// `text` with typographic quotes and apostrophes folded to straight ones: the recogniser reads a curly `’` as `'` (SimWalk#232), and the comparison is of letters, not of which mark was drawn.
    private static func straightened(_ text: String) -> String {
        String(text.map { character in
            switch character {
            case "\u{2018}", "\u{2019}", "\u{201B}": "'"
            case "\u{201C}", "\u{201D}": "\""
            default: character
            }
        })
    }

    private static func collapsed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// The drawn-text path's reading of a recognised line as the labels it holds: the recogniser joins labels drawn side by side at one height into one line, and a label drawn on two lines has its first line in another.
extension TruncatedTextAudit {
    /// One cut-short label's last line: its text, ending at an ellipsis, and the part of the recognised line it was read from.
    struct DrawnSegment {
        let text: String
        let line: MirrorTextLine
    }

    /// `line` split into the pieces that each end at an ellipsis, placed along the line by their share of its characters; text after the last ellipsis is not cut short and is left out.
    static func cutShortSegments(of line: MirrorTextLine) -> [DrawnSegment] {
        let characters = Array(line.text.trimmingCharacters(in: .whitespacesAndNewlines))
        var ends: [Int] = []
        var index = 0
        while index < characters.count {
            if characters[index] == "…" {
                ends.append(index + 1)
            } else if characters[index] == ".", index + 2 < characters.count, characters[index + 1] == ".", characters[index + 2] == "." {
                ends.append(index + 3)
                index += 2
            }
            index += 1
        }
        var start = 0
        var segments: [DrawnSegment] = []
        for end in ends {
            defer { start = end }
            guard let first = (start ..< end).first(where: { !characters[$0].isWhitespace }) else { continue }
            let text = String(characters[first ..< end])
            guard endsCutShort(text) else { continue }
            segments.append(DrawnSegment(text: text, line: placed(text, from: first, to: end, of: characters.count, in: line)))
        }
        // One piece that is the whole line is the line itself, not a recomputation of it.
        if segments.count == 1, segments[0].text == String(characters) {
            return [DrawnSegment(text: segments[0].text, line: line)]
        }
        return segments
    }

    /// The word of the recognised line directly above segment `index` of `line` that belongs over it, when there is one.
    ///
    /// Only the shape that shows a row of labels each wrapped onto two lines is paired: a line of several cut-short segments under a line with exactly as many words, itself not cut short. Anything else above a cut-short line — a heading over one label, a second cut-short row — is other text, and quoting it as the label's first line would misstate what was drawn, so the segment is reported alone.
    static func firstLine(above segments: [DrawnSegment], at index: Int, of line: MirrorTextLine, among lines: [MirrorTextLine]) -> String? {
        guard segments.count > 1 else { return nil }
        let segment = segments[index].line
        let top = line.centreY - line.height / 2
        let span = (segment.centreX - segment.width / 2) ... (segment.centreX + segment.width / 2)
        let candidates = lines.filter { other in
            other != line && other.centreY < line.centreY && abs(top - (other.centreY + other.height / 2)) <= line.height
                && other.centreX - other.width / 2 <= span.upperBound && other.centreX + other.width / 2 >= span.lowerBound
        }
        guard let above = candidates.min(by: { abs(top - ($0.centreY + $0.height / 2)) < abs(top - ($1.centreY + $1.height / 2)) }),
              !endsCutShort(above.text)
        else {
            return nil
        }
        let words = placedWords(of: above)
        guard words.count == segments.count else { return nil }
        return words[index].text
    }

    /// `line`'s whitespace-separated words, each placed along the line by its share of the characters.
    private static func placedWords(of line: MirrorTextLine) -> [MirrorTextLine] {
        let characters = Array(line.text.trimmingCharacters(in: .whitespacesAndNewlines))
        var words: [MirrorTextLine] = []
        var index = 0
        while index < characters.count {
            guard !characters[index].isWhitespace else {
                index += 1
                continue
            }
            let start = index
            while index < characters.count, !characters[index].isWhitespace {
                index += 1
            }
            words.append(placed(String(characters[start ..< index]), from: start, to: index, of: characters.count, in: line))
        }
        return words
    }

    /// `text`, characters `start` to `end` of `total` along `line`, as a line of its own at the same height.
    private static func placed(_ text: String, from start: Int, to end: Int, of total: Int, in line: MirrorTextLine) -> MirrorTextLine {
        let middle = (Double(start + end) / 2) / Double(total)
        return MirrorTextLine(text: text, centreX: line.centreX - line.width / 2 + line.width * middle, centreY: line.centreY, width: line.width * Double(end - start) / Double(total), height: line.height, confidence: line.confidence)
    }
}
