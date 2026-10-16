//
// Copyright © Agulhas Labs
//

import Foundation

/// How an audit words what it could and could not look at — the verdict's qualifications, the figure it is a verdict over, and the residue line that names the screens.
///
/// Shared by every rule's summary and by the combined `bundle audit` answer, because coverage is the bundle's and not a rule's: two phrasings of "3 screens were never opened" would let the rules' answers disagree about the same bundle.
struct AuditCoverageStatement {
    private let coverage: BundleAuditScope.Coverage

    init(_ coverage: BundleAuditScope.Coverage) {
        self.coverage = coverage
    }

    /// The qualification clauses the verdict carries — absent, each, when its count is zero.
    var qualifications: [String] {
        [
            AnswerVerdict.qualification(coverage.screensNotRead.count, "screen", "holding no captures at all"),
            AnswerVerdict.qualification(coverage.screensPartlyRead.count, "screen", "captured only in part"),
            AnswerVerdict.qualification(coverage.screensWrongScreen.count, "screen", "that captured a different screen than the walkbook expected"),
            AnswerVerdict.qualification(coverage.unsettledCaptures.count, "capture", "read before its accessibility tree settled, or while it held only the app's chrome"),
        ].compactMap(\.self)
    }

    /// The figure the verdict carries: what this verdict is a verdict over.
    var audited: String {
        "audited \(coverage.screensRead.count) of \(coverage.screensInWalk) screen\(coverage.screensInWalk == 1 ? "" : "s")"
    }

    /// Which screens the verdict's coverage qualifications are about — and nothing at all when it has none.
    ///
    /// The figure moved to the verdict line and the names stayed here, because they are two different things a reader needs: how much of the walk this speaks for, and *which* part it does not. Where the audit read everything, this line would be the verdict's own words again, so it is not printed — the contract's rule that an empty section is nothing, applied to a section that is merely redundant.
    var line: String? {
        guard !coverage.isComplete else { return nil }
        var clauses: [String] = []
        if !coverage.screensNotRead.isEmpty {
            let count = coverage.screensNotRead.count
            clauses.append("\(count) hold\(count == 1 ? "s" : "") no captures at all (\(coverage.screensNotRead.joined(separator: ", ")))")
        }
        if !coverage.screensPartlyRead.isEmpty {
            let count = coverage.screensPartlyRead.count
            clauses.append("\(count) \(count == 1 ? "was" : "were") captured only in part (\(coverage.screensPartlyRead.joined(separator: ", ")))")
        }
        if !coverage.screensWrongScreen.isEmpty {
            let count = coverage.screensWrongScreen.count
            clauses.append("\(count) captured a different screen than expected (\(coverage.screensWrongScreen.joined(separator: ", ")))")
        }
        var line = audited
        if !clauses.isEmpty {
            line += " — \(clauses.joined(separator: "; ")); this verdict says nothing about them"
        }
        // Its own clause rather than one of the above, because the qualification is a different one: these
        // screens were read, and what was read of them may not be what the screen settled into. "Says
        // nothing about them" would be the wrong claim, and dropping them would be the old silence.
        if !coverage.unsettledCaptures.isEmpty {
            let count = coverage.unsettledCaptures.count
            let named = coverage.unsettledCaptures.map { "\($0.screenID)/\($0.stateSlug)" }.joined(separator: ", ")
            line += clauses.isEmpty ? " — " : ", and "
            line += "\(count) capture\(count == 1 ? " was" : "s were") read whose accessibility tree had not settled, or held only the app's chrome (\(named)), so what was found there is of a screen still assembling itself or not yet arrived"
        }
        return line
    }
}
