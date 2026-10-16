//
// Copyright © Agulhas Labs
//

import Foundation

/// Renders a MirrorObservation as an `Answer` (Brief §8 "The observation").
///
/// **Text read by OCR, and the header says so; it never says what the screen shows.** Vision can misread, drop or invent a line, so the answer states the method, qualifies a read of no text rather than passing it, and marks each line's low confidence. Pure: the clock time takes its time zone as a parameter.
public struct MirrorObservationSummary {
    /// How many gone texts are quoted before the rest are counted.
    static let goneLimit = 10

    /// The answer for `observation`.
    ///
    /// - Parameters:
    ///   - match: When given, only lines containing it (case-insensitive) are listed; the verdict's counts still cover the whole screen.
    ///   - timeZone: Where the clock time is read.
    public static func answer(_ observation: MirrorObservation, match: String? = nil, timeZone: TimeZone) -> Answer {
        let read = observation.read
        let change = observation.before.map { read.change(from: $0) }
        let window = observation.window
        return Answer(
            header: "mirror \(observation.label) · \(MirrorSummaryText.windowClause(window)) · text read by OCR",
            verdict: verdict(observation, change: change),
            residue: residue(observation, change: change, match: match, timeZone: timeZone),
            weighing: read.pixelSize.map { ContextSaving(screenshotTokens: [ImageTokenEstimate.tokens(of: $0)], treeBytes: 0, servedBytes: 0) }
        )
    }

    private static func verdict(_ observation: MirrorObservation, change: MirrorRead.Change?) -> AnswerVerdict {
        let read = observation.read
        let bound = observation.boundMilliseconds
        let noText = "no text read: the screen may be blank, locked, or Screen Recording is not granted to this process"
        guard !read.lines.isEmpty else {
            return .qualified([noText], detail: "")
        }
        let counts = [MirrorSummaryText.counted(read.lines.count, "line"), change.map { "+\($0.added.count) −\($0.gone.count) since before" }].compactMap(\.self).joined(separator: " · ")
        return switch observation.reason {
        case nil:
            .unqualified("\(counts)\(change?.isEmpty == true ? " · text unchanged; lines moved" : "") · settled in \(observation.millisecondsToRead) ms over \(observation.reads) reads")
        case .noVisibleChange?:
            .qualified(["no visible text changed within \(bound) ms"], detail: counts)
        case .stillChanging?:
            .qualified(["not settled within \(bound) ms; the last read is shown"], detail: counts)
        }
    }

    private static func residue(_ observation: MirrorObservation, change: MirrorRead.Change?, match: String?, timeZone: TimeZone) -> [String] {
        let read = observation.read
        let size = read.pixelSize.map { "\($0.width)×\($0.height) px" } ?? "size unknown"
        let after = observation.action == nil ? "" : " (+\(observation.millisecondsToRead) ms after the event)"
        var lines = ["capture \(read.path.path) · \(size) · \(MirrorSummaryText.clock(read.capturedAt, timeZone: timeZone))\(after)"]
        let marked = markedLines(read, before: observation.before)
        for (index, line) in read.lines.enumerated() where match.map({ line.text.localizedCaseInsensitiveContains($0) }) ?? true {
            lines.append(MirrorSummaryText.lineText(line, marker: marked.contains(index) ? "+" : " "))
        }
        if let gone = change?.gone, !gone.isEmpty {
            lines.append("gone: \(MirrorSummaryText.quoted(gone, limit: goneLimit, noun: "more"))")
        }
        return lines
    }

    /// The indexes of the lines to mark `+`: exactly the lines `change` counts as added, so a line equivalent to a before line, a doubtful line and a status-band line are never marked.
    private static func markedLines(_ read: MirrorRead, before: MirrorRead?) -> Set<Int> {
        before.map { Set(read.addedIndexes(from: $0)) } ?? []
    }
}
