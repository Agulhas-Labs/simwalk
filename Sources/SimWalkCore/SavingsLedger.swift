//
// Copyright © Agulhas Labs
//

import Foundation

/// The one way a total over many usage lines is summed, so `simwalk usage` and the status line cannot come to different figures from the same log.
///
/// Each line states what its own answer stood in for, which is right for that answer and wrong to add up: a walk, then an audit of its bundle, then a screen query over it all stand in for the same screenshots. The ledger walks lines in log order and prices a screenshot the first time it sees its identity (``ContextSaving/screenshotIdentities``); a later line over the same pixels adds no tokens for it. **Every served byte is charged, though**: a line whose screenshots were all priced already still put its answer in front of the reader, and so did a line with no screenshots to price. The saving is computed once, over the totals, and floored at zero there and nowhere else — a floor per line would let a repeat read's bytes go uncharged. A line with no `priced` field — written before the field existed, or a live screen with no file — is counted whole, as its own line states it.
public struct SavingsLedger: Codable, Equatable, Sendable {
    /// The identities already priced, carried between status-line renders so a later render does not count them again.
    public var claimed: Set<String> = []

    /// The tokens of every screenshot priced so far, each once.
    public private(set) var screenshotTokens = 0

    /// The bytes of every answer that recorded its size, whether or not it priced anything.
    public private(set) var servedBytes = 0

    /// How many screenshots were priced, each once.
    public private(set) var screenshots = 0

    public init() {}

    /// What the log saved: the screenshots priced, less everything served, never below zero.
    public var saved: Int {
        ContextSaving.saved(imageTokens: screenshotTokens, servedBytes: servedBytes)
    }

    /// Takes one line into the totals; a line that recorded no answer size changes nothing.
    public mutating func add(_ entry: UsageLog.Entry) {
        guard let answerBytes = entry.answerBytes else { return }
        servedBytes += answerBytes
        guard let imageTokens = entry.imageTokens else { return }
        guard let priced = entry.priced else {
            screenshotTokens += imageTokens
            screenshots += entry.screenshots ?? 0
            return
        }
        for item in priced {
            let parts = item.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let weight = Int(parts[1]), claimed.insert(String(parts[0])).inserted else { continue }
            screenshotTokens += weight
            screenshots += 1
        }
    }
}
