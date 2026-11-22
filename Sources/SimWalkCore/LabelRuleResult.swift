//
// Copyright © Agulhas Labs
//

import Foundation

/// What one label rule found in one capture or across a bundle, with the count it looked at.
///
/// The count is the rule's arithmetic: "none found" beside "41 controls examined" is a check that ran, where "none found" alone could equally be a rule that matched nothing because nothing of its kind was there to match.
public struct LabelRuleResult: Equatable, Sendable {
    /// How many controls the rule examined.
    public var examined: Int
    /// What it objected to.
    public var findings: [LabelFinding]
    /// How many captures the rule could not check, for a rule that needs more than the tree (a screenshot it could not read); the answer says so beside the count.
    public var unchecked: Int
    /// How many of the `unchecked` captures had a readable screenshot that recognition failed on; the rest had no screenshot to read.
    public var recognitionFailed: Int
    /// The cause of the first recognition failure, for the answer to name; none when recognition never failed.
    public var recognitionFailure: String?
    /// How many runs extend past the screen's width inside a horizontal scroller, which scrolls sideways by design, so the rule did not report them; the answer says so beside the count (SimWalk#287).
    public var inHorizontalScroller: Int
    /// The screen of each such run, in order and repeated, so a line can name the screens.
    public var inHorizontalScrollerScreens: [String] = []
    /// How many recognised lines lie outside every text run, for the rule that examines them too (`truncatedText`); none for a rule that does not, whose heading then counts only what it examined.
    public var drawnLinesOutside: Int?
    /// How many text-carrying elements the rule did not judge because they are not wholly on screen, for the rule that judges only what the capture shows (`truncatedText`); the verdict and the heading say so, so an audit that skipped most of a tall screen never reads clean.
    public var offScreen: Int = 0

    public init(examined: Int = 0, findings: [LabelFinding] = [], unchecked: Int = 0, recognitionFailed: Int = 0, recognitionFailure: String? = nil, inHorizontalScroller: Int = 0) {
        self.examined = examined
        self.findings = findings
        self.unchecked = unchecked
        self.recognitionFailed = recognitionFailed
        self.recognitionFailure = recognitionFailure
        self.inHorizontalScroller = inHorizontalScroller
    }

    /// Two results as one, in order.
    mutating func absorb(_ other: LabelRuleResult) {
        examined += other.examined
        findings += other.findings
        unchecked += other.unchecked
        recognitionFailed += other.recognitionFailed
        recognitionFailure = recognitionFailure ?? other.recognitionFailure
        inHorizontalScroller += other.inHorizontalScroller
        inHorizontalScrollerScreens += other.inHorizontalScrollerScreens
        offScreen += other.offScreen
        if let outside = other.drawnLinesOutside {
            drawnLinesOutside = (drawnLinesOutside ?? 0) + outside
        }
    }
}
