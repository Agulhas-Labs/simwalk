//
// Copyright © Agulhas Labs
//

import Foundation

/// What one capture of the mirrored phone says: its recognised lines in reading order, and the capture's own facts.
///
/// **The lines are put in reading order here, not left in the recogniser's, because order is part of what two reads are compared on.** Vision returns observations in no promised order, so two reads of one unchanged screen could list the same lines differently and disagree for no reason. Rows run top to bottom, and lines whose vertical centres are within half the smaller line's height of each other share a row, left to right — a pure function of the lines, so a test replays it on scripted ones. `capturedAt` arrives as a parameter for the determinism rule's sake: the core never asks the clock.
public struct MirrorRead: Equatable, Sendable {
    /// The capture the lines were read from.
    public let path: URL
    /// The capture's size in pixels, or `nil` when its header was not a PNG's.
    public let pixelSize: PNGSize?
    /// When the capture was taken.
    public let capturedAt: Date
    /// Every recognised line in reading order, the status bar's included — they are served, and only left out of comparisons.
    public let lines: [MirrorTextLine]

    /// - Parameter lines: In any order; they are stored in reading order.
    public init(path: URL, pixelSize: PNGSize?, capturedAt: Date, lines: [MirrorTextLine]) {
        self.path = path
        self.pixelSize = pixelSize
        self.capturedAt = capturedAt
        self.lines = Self.readingOrder(lines)
    }

    /// `lines` as rows top to bottom, left to right within a row.
    ///
    /// A line joins the current row when its vertical centre is within half the smaller of the two heights of the row's first line; the first line is the anchor so a row cannot drift down a staircase of lines each close to the last.
    public static func readingOrder(_ lines: [MirrorTextLine]) -> [MirrorTextLine] {
        let byHeight = lines.sorted { $0.centreY < $1.centreY }
        var rows: [[MirrorTextLine]] = []
        for line in byHeight {
            if let anchor = rows.last?.first,
               abs(line.centreY - anchor.centreY) <= min(line.height, anchor.height) / 2
            {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.flatMap { $0.sorted { $0.centreX < $1.centreX } }
    }
}
