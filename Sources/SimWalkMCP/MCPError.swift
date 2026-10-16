//
// Copyright © Agulhas Labs
//

import SimWalkCore

/// A tool-level failure, reported inside the tool result rather than as a protocol error.
///
/// The distinction is the client's: a JSON-RPC error means the *call* was malformed and the model can do nothing with it, where a tool result marked `isError` is an answer the model reads — which is what a refusal is. So everything a walk can refuse over arrives here and comes back as `refused — …`, the same words the CLI writes to stderr.
public struct MCPError: Error, CustomStringConvertible {
    public let message: String
    /// Which kind this failure is, for the usage log — stated by every constructor, with no default to fall back on.
    ///
    /// `MCPToolInvocation`'s constructions state `.inputRefused`: a tool name or an argument this server received is always a bad argument. `MCPToolRunner.parsed` restates two different failures in the command's own words: a `validate()` refusal of a caller's own argument (`.inputRefused`) and an ArgumentParser parse failure over a vector `MCPToolInvocation` had already checked (`.toolError` — the command and the MCP face disagreeing, which is not something any caller typed).
    ///
    /// **No default, deliberately.** A default of `.inputRefused` made a future constructor that forgot the argument silently become the one kind `simwalk usage` leaves out of its headline — the unsafe direction for a failure nothing has looked at. Without one, forgetting is a compile error.
    public let kind: UsageFailureKind

    public init(message: String, kind: UsageFailureKind) {
        self.message = message
        self.kind = kind
    }

    public var description: String {
        message
    }
}

extension MCPError: UsageFailureClassifiable {
    public var usageFailureKind: UsageFailureKind {
        kind
    }
}
