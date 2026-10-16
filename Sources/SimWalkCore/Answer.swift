//
// Copyright © Agulhas Labs
//

import Foundation

/// One answer in the shape the contract states: a header saying what it was measured against, the verdict, the residue, and what it saved.
///
/// The shape is shared with Sift — the contract is written down once, in Sift's answer contract (Docs/AnswerContract.md in github.com/Agulhas-Labs/sift), and both tools answer to it — so a reader who has learned to skim one has learned to skim the other. Header first (§1), the verdict word leading its line and counters after the numbers that can go down (§2), only the residue and never an empty heading (§3), every figure with its arithmetic (§4).
///
/// **The context line is last and states this answer's own cost**, which is the one figure the answer cannot know before it is rendered: what it saved depends on what it costs, and what it costs includes the line saying so. So the served figure is solved for rather than guessed — the body is rendered once and the line priced against a total that includes itself, the terminating newline a face writes included, so the figure is what `wc -c` reports. Where the two do not settle the larger cost is kept, because a served figure that is a byte high understates the saving and one that is a byte low overstates it, and only one of those is allowed.
public struct Answer: Equatable, Sendable {
    /// What this answer was measured against.
    public let header: String

    /// The word the caller acts on.
    public let verdict: AnswerVerdict

    /// What the caller has to look at — never the material it was derived from, and nothing at all where there is nothing.
    public let residue: [String]

    /// What this answer stands in for, unpriced — `nil` when it stands in for nothing.
    public let weighing: ContextSaving?

    public init(header: String, verdict: AnswerVerdict, residue: [String] = [], weighing: ContextSaving? = nil) {
        self.header = header
        self.verdict = verdict
        self.residue = residue
        self.weighing = weighing
    }

    /// The whole answer, as a face prints it.
    public var text: String {
        rendered.text
    }

    /// The saving this answer's own bytes price it at — what the usage log records, and `nil` when nothing was weighed.
    public var saving: ContextSaving? {
        rendered.saving
    }

    /// How many times the served figure is allowed to be re-solved before the larger of the two is kept.
    private static let pricingPasses = 3

    /// The two newlines an answer costs beyond its own lines' bytes: the one joining the context line to the body, and the one a face writes after the last line.
    ///
    /// The second is the difference between a figure that is nearly right and one a reader can check: `simwalk bundle inspect … | wc -c` counts the terminator, and a served figure one byte under it makes the arithmetic beside every answer wrong in the direction that flatters the tool.
    private static let newlines = 2
}

private extension Answer {
    /// The rendered answer and the saving its own size priced, solved together.
    var rendered: (text: String, saving: ContextSaving?) {
        let body = ([header, verdict.line] + residue).joined(separator: "\n")
        guard let weighing else { return (body, nil) }
        // Each pass costs the answer more than the last (the line it is about to add), so this rises
        // towards the true total and stops the moment a pass would lower it — never below what the
        // answer actually costs.
        var saving = weighing.served(body.utf8.count + Self.newlines)
        for _ in 0 ..< Self.pricingPasses {
            let served = body.utf8.count + Self.newlines + saving.line.utf8.count
            guard served > saving.servedBytes else { break }
            saving = weighing.served(served)
        }
        return (body + "\n" + saving.line, saving)
    }
}
