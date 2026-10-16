//
// Copyright © Agulhas Labs
//

/// What a transcript scan has to carry from one line to the next.
///
/// One thing, and it is the calls that have gone out and not yet come back: a `tool_use` block is counted where it appears, and only its *result* can say the call never actually ran — so the id has to survive until the result arrives, which in a live transcript is several lines later and in a resumed session is a later render entirely.
public struct SessionScanState: Codable, Equatable, Sendable {
    /// Counted calls awaiting a result, by `tool_use_id`, each remembering whether it was a walk so a retraction takes back what it added.
    ///
    /// Dropped the moment a result arrives, so this holds one entry at most in normal use — which is also what keeps the byte pre-filter cheap, since every id in it is searched for on every line.
    public var pending: [String: Bool] = [:]

    public init() {}
}
