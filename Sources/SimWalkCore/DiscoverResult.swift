//
// Copyright © Agulhas Labs
//

import Foundation

/// What a `discover` crawl drafted, and everything it saw and left alone.
public struct DiscoverResult: Equatable, Sendable {
    /// The draft: one screen per distinct form, each with its route from launch.
    public let walkbook: Walkbook
    /// Every control not tapped, grouped by screen in draft order and visually within one.
    public let skipped: [DiscoverSkip]
    /// Screens reached whose form one already drafted, so neither drafted nor crawled again.
    public let duplicates: [Duplicate]
    /// The bounds the crawl ran under.
    public let depth: Int
    public let maxScreens: Int
    /// The drafted screens whose list may continue below the rows the app loaded, which were not read (``DiscoverClassifier/listMayContinue(_:)``).
    public let belowTheFold: [String]

    public init(walkbook: Walkbook, skipped: [DiscoverSkip], duplicates: [Duplicate], depth: Int, maxScreens: Int, belowTheFold: [String] = []) {
        self.walkbook = walkbook
        self.skipped = skipped
        self.duplicates = duplicates
        self.depth = depth
        self.maxScreens = maxScreens
        self.belowTheFold = belowTheFold
    }

    /// How many affordances were left unvisited for `reason` — a bound is never reached in silence.
    public func unvisited(_ reason: DiscoverSkip.Reason) -> Int {
        skipped.count { $0.reason == reason }
    }

    /// The draft as `session save` writes a walkbook, refused unless the bytes load as one.
    public func encoded() throws -> Data {
        let data = try LiveSessionSave.encoded(walkbook)
        _ = try WalkbookLoader.load(from: data, source: "discover draft")
        return data
    }

    /// Writes the draft to `url`, refused when a file is already there — checked again by the rename itself, so a file that appears mid-crawl is never replaced.
    ///
    /// The bytes are ``encoded()``'s, loaded back as a walkbook first, and land whole or not at all, as `session save` writes.
    public func write(to url: URL) throws {
        let data = try encoded()
        let target = try LiveSessionSave.resolved(url)
        let written: Bool
        do {
            written = try LiveSessionChannel.write(data, to: target, exclusively: true)
        } catch let LiveSessionError.notWritable(_, reason) {
            throw DiscoverError.notWritable(path: url.path, reason: reason)
        }
        guard written else { throw DiscoverError.outputExists(path: url.path) }
    }

    /// The answer a face prints: `ok` with the screens drafted and controls skipped, `qualified` when a bound was reached, an alert ended a branch, the crawl could not get back to a screen or a screen's list may continue below the rows read, then ``lines()``.
    public func answer(header: String, output: String) -> Answer {
        let qualifications = [
            AnswerVerdict.qualification(unvisited(.beyondDepth), "affordance", "beyond depth \(depth)"),
            AnswerVerdict.qualification(unvisited(.beyondMaxScreens), "affordance", "beyond max screens \(maxScreens)"),
            AnswerVerdict.qualification(unvisited(.alertEndsBranch), "branch", "ended by an alert"),
            AnswerVerdict.qualification(unvisited(.couldNotReturn), "control", "on a screen the crawl could not return to"),
            belowTheFold.isEmpty ? nil : belowTheFold.count == 1 ? "1 screen's list may continue below the fold, not read" : "\(belowTheFold.count) screens' lists may continue below the fold, not read",
        ].compactMap(\.self)
        let screens = walkbook.screens.count
        let detail = "\(screens) screen\(screens == 1 ? "" : "s") drafted to \(output) · \(skipped.count) skipped"
        return Answer(header: header, verdict: .reporting(qualifications: qualifications, detail: detail), residue: lines())
    }

    /// The bounds reached, the screens whose list may continue unread, the duplicates, then the skipped list: one line per control, under its screen.
    public func lines() -> [String] {
        var lines: [String] = []
        for (reason, bound) in [(DiscoverSkip.Reason.beyondDepth, "depth \(depth)"), (.beyondMaxScreens, "max screens \(maxScreens)")] {
            let count = unvisited(reason)
            if count > 0 {
                lines.append("\(bound) reached: \(count) affordance\(count == 1 ? "" : "s") not visited")
            }
        }
        lines += belowTheFold.map { "\($0): the list may continue below the rows the app loaded; rows there were not read" }
        lines += duplicates.map { "reached again as \($0.screenID): \($0.route.map(\.description).joined(separator: " → "))" }
        for (screen, entries) in AuditRowFormat.screensInOrder(skipped, screen: \.screenID) {
            lines.append("\(screen): \(entries.count) control\(entries.count == 1 ? "" : "s") not tapped")
            lines += entries.map { "  \($0.line)" }
        }
        return lines
    }
}

public extension DiscoverResult {
    /// A route that reached a screen whose form was already drafted.
    struct Duplicate: Equatable, Sendable {
        /// The route that reached it again.
        public let route: [Walkbook.RouteStep]
        /// The drafted screen it has the form of.
        public let screenID: String

        public init(route: [Walkbook.RouteStep], screenID: String) {
            self.route = route
            self.screenID = screenID
        }
    }
}
