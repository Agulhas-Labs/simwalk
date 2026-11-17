//
// Copyright © Agulhas Labs
//

import Foundation

/// What a step changed on the screen: the text elements that appeared and disappeared between the read before it and the read after, each in `bundle screen`'s line form (`label = value · Type · x,y w×h`).
///
/// **The lines are `bundle screen`'s own** (``BundleScreenQuery/lines(of:)``), so an element in the delta reads exactly as it would in a `session read` and a route written from either names the same labels. An element that moved is one line gone and one come — its frame is part of what a reader acts on, so a moved element is a changed one.
///
/// **An element read again a pulse apart is neither.** A walk cannot turn SwiftUI's animations off, so an endlessly pulsing button is read at another phase after every step, a point or two off and a few points larger, and listing it as one `-` and one `+` line reported an element appearing that never left. A line gone and one come with the same label, value and type whose frames are steady with each other (``AXNode/Frame/isSteady(with:)``, the 8% that holds a pulse) are dropped as a pair before counting; a slide moves further than that and stays listed.
///
/// **A trait that changed on a screen that stayed is a third kind of line** (SimWalk#251): `~ <the line> · selected`, `not selected`, `enabled` or `disabled`, two joined by a comma. A tile the tap selected moves no frame and changes no label, so without it a step whose whole effect was a selection read as having changed nothing. Only between two reads of one screen (``SameScreenChange/traitChanges(from:to:)``): after a push every element is new and a trait carries no news.
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
    /// How many elements' selection or enablement changed on a screen the step did not leave.
    public let changedCount: Int
    /// The first ``cap`` of those, in the after-read's order, each a line ending in what changed.
    public let changed: [String]

    /// The fraction of the screen's picture that changed, 0…1, when the tree has no text and the screenshots stood in for it (SimWalk#150); `nil` otherwise.
    public let pixelsChanged: Double?

    /// The delta from `before` to `after`, each line matched once — so a line listed twice before and once after is one disappeared.
    public init(from before: AXNode, to after: AXNode, pixels: (before: PixelSignature, after: PixelSignature)? = nil) {
        let beforeElements = BundleScreenQuery.elements(of: before)
        let afterElements = BundleScreenQuery.elements(of: after)
        let (appeared, disappeared) = Self.withoutPulses(
            appeared: Self.unmatched(afterElements, against: beforeElements),
            disappeared: Self.unmatched(beforeElements, against: afterElements)
        )
        appearedCount = appeared.count
        disappearedCount = disappeared.count
        self.appeared = Array(appeared.prefix(Self.cap))
        self.disappeared = Array(disappeared.prefix(Self.cap))
        let changed = SameScreenChange.traitChanges(from: before, to: after).map { "\(BundleScreenQuery.line($0.node)) · \($0.words)" }
        changedCount = changed.count
        self.changed = Array(changed.prefix(Self.cap))
        pixelsChanged = pixels.map { $0.before.changedFraction(to: $0.after) }
    }

    /// A delta written before the changed lines existed decodes as one with none, as one written before the pixels did decodes without them.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appearedCount = try container.decode(Int.self, forKey: .appearedCount)
        disappearedCount = try container.decode(Int.self, forKey: .disappearedCount)
        appeared = try container.decode([String].self, forKey: .appeared)
        disappeared = try container.decode([String].self, forKey: .disappeared)
        changedCount = try container.decodeIfPresent(Int.self, forKey: .changedCount) ?? 0
        changed = try container.decodeIfPresent([String].self, forKey: .changed) ?? []
        pixelsChanged = try container.decodeIfPresent(Double.self, forKey: .pixelsChanged)
    }

    /// Whether the step changed nothing a reader lists.
    public var isEmpty: Bool {
        appearedCount == 0 && disappearedCount == 0 && changedCount == 0
    }

    /// The delta as an answer's residue: a count line, then each appeared line marked `+`, each disappeared one `-` and each changed one `~`.
    ///
    /// The count line names changed elements only when there are some, so a delta without any reads exactly as it did before they were counted.
    public var residue: [String] {
        let counted = "delta: \(appearedCount) appeared, \(disappearedCount) disappeared" + (changedCount > 0 ? ", \(changedCount) changed" : "")
        var lines = [isEmpty ? "delta: nothing appeared or disappeared" : counted]
        if let pixelsChanged {
            lines.append(Self.pixelsLine(pixelsChanged))
        }
        guard !isEmpty else { return lines }
        lines += Self.section("+", appeared, of: appearedCount)
        lines += Self.section("-", disappeared, of: disappearedCount)
        lines += Self.section("~", changed, of: changedCount)
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

    /// `elements` less one whose line matches one of `other`'s each, in `elements`' own order.
    private static func unmatched(_ elements: [AXNode], against other: [AXNode]) -> [AXNode] {
        var remaining = Dictionary(other.map { (BundleScreenQuery.line($0), 1) }, uniquingKeysWith: +)
        return elements.filter { element in
            let line = BundleScreenQuery.line(element)
            guard let count = remaining[line], count > 0 else { return true }
            remaining[line] = count - 1
            return false
        }
    }

    /// The appeared and disappeared elements as lines, less each pair that is one element read a pulse apart: the same label, value and type at frames steady with each other.
    private static func withoutPulses(appeared: [AXNode], disappeared: [AXNode]) -> (appeared: [String], disappeared: [String]) {
        var appeared = appeared
        let disappeared = disappeared.filter { gone in
            let pulse = appeared.firstIndex {
                $0.label == gone.label && $0.value == gone.value && $0.type == gone.type && gone.frame.isSteady(with: $0.frame)
            }
            guard let pulse else { return true }
            appeared.remove(at: pulse)
            return false
        }
        return (appeared.map(BundleScreenQuery.line), disappeared.map(BundleScreenQuery.line))
    }

    /// One kind's lines, each marked `+` (appeared), `-` (disappeared) or `~` (changed), and a line for those past the cap.
    private static func section(_ marker: String, _ lines: [String], of count: Int) -> [String] {
        let more = count > lines.count ? ["\(marker) … \(count - lines.count) more — `session read` lists them all"] : []
        return lines.map { "\(marker) \($0)" } + more
    }
}
