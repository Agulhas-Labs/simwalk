//
// Copyright © Agulhas Labs
//

/// The eight tools the MCP face exposes — `session` one tool over its six actions and `mirror` one over its six, since every definition here is re-sent on every agent turn.
///
/// A type rather than a string, because it is what the server hands the face that does the work: an exhaustive switch there cannot fall through to an "unknown tool" branch that only exists to be unreachable — the name is refused once, where it arrives, and every later step is about a verb that exists.
public enum SimWalkTool: String, CaseIterable, Sendable {
    case walk
    case validate
    case inspect
    case audit
    case diff
    case oracle
    case session
    case mirror
}

public extension SimWalkTool {
    /// The verb the usage log records, which is the CLI's own name for it.
    ///
    /// `inspect` and `audit` are `bundle inspect` and `bundle audit` on the command line and are logged as such, so `simwalk usage` reports one row per verb rather than one per face — the log is meant to answer "what is this tool asked to do", and the answer must not split because the same question arrived over a different transport. The MCP name stays short because it is spent in every session's tool list.
    var logName: String {
        switch self {
        case .walk: "walk"
        case .validate: "validate"
        case .inspect: "bundle inspect"
        case .audit: "bundle audit"
        case .diff: "bundle diff"
        case .oracle: "bundle oracle"
        case .session: "session"
        case .mirror: "mirror"
        }
    }

    /// What a dry run of `walk` is logged as, on either face — the one spelling `WalkCommand.dryRunLogName` and `MCPToolInvocation` both read, so `simwalk usage` prices a probe apart from the walks it is minutes cheaper than.
    static var walkDryRunLogName: String {
        "walk --dry-run"
    }
}
