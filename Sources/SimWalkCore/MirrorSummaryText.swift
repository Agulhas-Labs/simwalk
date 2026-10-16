//
// Copyright © Agulhas Labs
//

import Foundation

/// The spellings the observation and burst summaries share: the window clause, the clock, one recognised line, a clipped quoted list.
struct MirrorSummaryText {
    /// `iPhone Mirroring <w>×<h> pt`.
    static func windowClause(_ window: MirrorWindowFrame) -> String {
        "iPhone Mirroring \(Int(window.width.rounded()))×\(Int(window.height.rounded())) pt"
    }

    /// `1 line`, `2 lines`: `noun` pluralised by a trailing `s` unless `count` is 1.
    static func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    /// `HH:mm:ss.SSS` in `timeZone`.
    static func clock(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    /// `+ .512,.118 .40×.02  Rowing`: the marker (`+` or a space), the centre to 3 decimals, the size to 2, ` ?0.30` after the box when the confidence is under 0.5, then the text after two spaces.
    static func lineText(_ line: MirrorTextLine, marker: String) -> String {
        let centre = MirrorFractionText.spell(x: line.centreX, y: line.centreY, decimals: 3)
        let size = "\(MirrorFractionText.spell(line.width, decimals: 2))×\(MirrorFractionText.spell(line.height, decimals: 2))"
        let doubt = line.confidence < 0.5 ? " ?\(String(format: "%.2f", line.confidence))" : ""
        return "\(marker) \(centre) \(size)\(doubt)  \(line.text)"
    }

    /// At most `limit` texts quoted and comma-separated, then `and k <noun>` for the rest, each text clipped to `clip` characters.
    static func quoted(_ texts: [String], limit: Int, noun: String, clip: Int = 40) -> String {
        var parts = texts.prefix(limit).map { "\"\(clipped($0, to: clip))\"" }
        if texts.count > limit {
            parts.append("and \(texts.count - limit) \(noun)")
        }
        return parts.joined(separator: ", ")
    }

    /// `text` cut to `limit` characters, an ellipsis marking the cut.
    static func clipped(_ text: String, to limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }
}
