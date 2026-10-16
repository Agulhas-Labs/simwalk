//
// Copyright © Agulhas Labs
//

import Foundation

/// Renders a MirrorBurst as an `Answer`: one line a frame, what each added and lost against the one before.
///
/// The first frame is compared against nothing, so everything below the status bar in it is added. A burst that was stopped, or that read no text in a frame, is qualified rather than passed.
public struct MirrorBurstSummary {
    /// How many texts a frame line names on each side before it stops.
    static let sideLimit = 5

    /// The answer for `burst`, naming `sheet` — the contact sheet written beside its frames — when there is one.
    public static func answer(_ burst: MirrorBurst, sheet: URL? = nil) -> Answer {
        var qualifications: [String] = []
        if let refusal = burst.stoppedBy {
            let frame: Int = if case let .beforeFrame(index) = refusal.moment {
                index
            } else {
                burst.frames.count + 1
            }
            let who = refusal.frontmost.isEmpty ? "no process" : refusal.frontmost
            qualifications.append("stopped before frame \(frame): \(who) was frontmost")
        }
        let blank = burst.frames.filter(\.read.lines.isEmpty).map(\.index)
        if !blank.isEmpty {
            qualifications.append("no text read in frame\(blank.count == 1 ? "" : "s") \(blank.map(String.init).joined(separator: ", ")): the screen may be blank, locked, or Screen Recording is not granted to this process")
        }
        var residue = ["frames \(burst.directory.path)"]
        if let sheet {
            residue.append("sheet \(sheet.path)")
        }
        var previous: MirrorRead?
        for frame in burst.frames {
            residue.append(frameLine(frame, previous: previous))
            previous = frame.read
        }
        return Answer(
            header: "mirror burst \(burst.label) · \(MirrorSummaryText.counted(burst.frames.count, "frame")) · \(MirrorSummaryText.windowClause(burst.window)) · text read by OCR",
            verdict: .reporting(qualifications: qualifications, detail: "\(burst.frames.count) of \(MirrorSummaryText.counted(burst.requested, "frame"))"),
            residue: residue,
            weighing: weighing(burst)
        )
    }

    private static func frameLine(_ frame: MirrorBurst.Frame, previous: MirrorRead?) -> String {
        let change = previous.map { frame.read.change(from: $0) }
            ?? MirrorRead.Change(added: frame.read.comparableLines.map(\.text), gone: [])
        var sides = [String]()
        if !change.added.isEmpty {
            sides.append("+ \(MirrorSummaryText.quoted(change.added, limit: sideLimit, noun: "more"))")
        }
        if !change.gone.isEmpty {
            sides.append("− \(MirrorSummaryText.quoted(change.gone, limit: sideLimit, noun: "more"))")
        }
        let index = frame.index < 10 ? "f0\(frame.index)" : "f\(frame.index)"
        let head = "\(index) +\(frame.millisecondsSinceTap) ms  +\(change.added.count) −\(change.gone.count)"
        return ([head] + [sides.joined(separator: " · ")].filter { !$0.isEmpty }).joined(separator: "  ")
    }

    private static func weighing(_ burst: MirrorBurst) -> ContextSaving? {
        let tokens = burst.frames.compactMap { $0.read.pixelSize.map(ImageTokenEstimate.tokens(of:)) }
        return tokens.isEmpty ? nil : ContextSaving(screenshotTokens: tokens, treeBytes: 0, servedBytes: 0)
    }
}
