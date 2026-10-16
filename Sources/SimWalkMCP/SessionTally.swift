//
// Copyright © Agulhas Labs
//

/// What one Claude Code session has asked of this tool, counted off its transcripts.
///
/// Counted from the transcript rather than from the usage log because the log knows only the calls this tool made *for a session* — an MCP call — and a session that drove the CLI from a shell would read as one that never used the tool at all.
public struct SessionTally: Codable, Equatable, Sendable {
    /// Every call the session made, through the MCP face or through a shell.
    public var calls = 0

    /// How many of those were walks.
    public var walks = 0

    public static func += (tally: inout SessionTally, other: SessionTally) {
        tally.calls += other.calls
        tally.walks += other.walks
    }
}

extension SessionTally {
    /// The count as the status line words it.
    ///
    /// Named after the verb only when every counted call *was* that verb: a walk is the expensive thing and the word a reader takes at face value, so a session that validated three walkbooks must not read as one that walked them. A shell call is a call and never a walk, because a command line can spell one a dozen ways and a count that guesses is a count that overstates.
    var counted: String {
        let noun = calls == walks ? "walk" : "call"
        return "\(calls) \(noun)\(calls == 1 ? "" : "s")"
    }
}
