//
// Copyright © Agulhas Labs
//

import Foundation

/// What a step changed on the screen: the text elements that appeared and disappeared between the read before it and the read after, each in `bundle screen`'s line form (`label = value · Type · x,y w×h`).
///
/// **The lines are `bundle screen`'s own** (``BundleScreenQuery/lines(of:)``), so an element in the delta reads exactly as it would in a `session read` and a route written from either names the same labels. An element that moved is one line gone and one come — its frame is part of what a reader acts on, so a moved element is a changed one.
///
/// **Counted in full, listed to a cap.** Both counts are exact; each list holds at most ``cap`` lines, in accessibility order, so a step onto a new screen of two hundred rows costs twenty lines and a count, and says so — the rest is a `session read` away.
public struct ScreenDelta: Codable, Equatable, Sendable {
    /// How many lines each list holds at most.
    public static let cap = 20

    /// How many elements appeared.
    public let appearedCount: Int
    /// How many elements disappeared.
    public let disappearedCount: Int
    /// The first ``cap`` elements that appeared, in the after-read's order.
    public let appeared: [String]
    /// The first ``cap`` elements that disappeared, in the before-read's order.
    public let disappeared: [String]

    /// The fraction of the screen's picture that changed, 0…1, when the tree has no text and the screenshots stood in for it (SimWalk#150); `nil` otherwise.
    public let pixelsChanged: Double?

    /// The delta from `before` to `after`, each line matched once — so a line listed twice before and once after is one disappeared.
    public init(from before: AXNode, to after: AXNode, pixels: (before: PixelSignature, after: PixelSignature)? = nil) {
        let beforeLines = BundleScreenQuery.lines(of: before)
        let afterLines = BundleScreenQuery.lines(of: after)
        let appeared = Self.unmatched(afterLines, against: beforeLines)
        let disappeared = Self.unmatched(beforeLines, against: afterLines)
        appearedCount = appeared.count
        disappearedCount = disappeared.count
        self.appeared = Array(appeared.prefix(Self.cap))
        self.disappeared = Array(disappeared.prefix(Self.cap))
        pixelsChanged = pixels.map { $0.before.changedFraction(to: $0.after) }
    }

    /// Whether the step changed nothing a reader lists.
    public var isEmpty: Bool {
        appearedCount == 0 && disappearedCount == 0
    }

    /// The delta as an answer's residue: a count line, then each appeared line marked `+` and each disappeared one `-`.
    public var residue: [String] {
        var lines = [isEmpty ? "delta: nothing appeared or disappeared" : "delta: \(appearedCount) appeared, \(disappearedCount) disappeared"]
        if let pixelsChanged {
            lines.append(Self.pixelsLine(pixelsChanged))
        }
        guard !isEmpty else { return lines }
        lines += Self.section("+", appeared, of: appearedCount)
        lines += Self.section("-", disappeared, of: disappearedCount)
        return lines
    }

    private static func pixelsLine(_ fraction: Double) -> String {
        let amount = fraction <= 0 ? "nothing changed" : "\(percentOfScreen(fraction)) of the screen changed"
        return "pixels: \(amount) (\(pixelHashReason))"
    }

    /// A fraction of the screen as a percent, `less than 1%` where it rounds to none.
    static func percentOfScreen(_ fraction: Double) -> String {
        let percent = Int((fraction * 100).rounded())
        return percent == 0 ? "less than 1%" : "\(percent)%"
    }

    /// Why a `pixels:` line is there at all, said the same way by a step's delta and a read (SimWalk#223).
    static var pixelHashReason: String {
        "the tree has no text, so the screen hash includes a pixel hash"
    }

    /// `lines` less one match in `other` each, in `lines`' own order.
    private static func unmatched(_ lines: [String], against other: [String]) -> [String] {
        var remaining = Dictionary(other.map { ($0, 1) }, uniquingKeysWith: +)
        return lines.filter { line in
            guard let count = remaining[line], count > 0 else { return true }
            remaining[line] = count - 1
            return false
        }
    }

    /// One side's lines, each marked `+` (appeared) or `-` (disappeared), and a line for those past the cap.
    private static func section(_ marker: String, _ lines: [String], of count: Int) -> [String] {
        let more = count > lines.count ? ["\(marker) … \(count - lines.count) more — `session read` lists them all"] : []
        return lines.map { "\(marker) \($0)" } + more
    }
}
