//
// Copyright © Agulhas Labs
//

/// A type that knows which ``UsageFailureKind`` its own failure is.
///
/// `TimedCall` and the MCP server each catch `any Error` from work that spans every module in this package, and a module low in the graph cannot see a type declared above it — `SimWalkMCP` depends only on this module, so a switch written where a catch happens could never be exhaustive over `SimWalkDriver`'s or `SimWalkCLI`'s own errors. A protocol declared here and conformed to wherever each error type is declared sidesteps that: `as?` against a protocol needs only the protocol to be visible, not the concrete type, so a module that has never heard of `SimulatorError` still classifies one correctly when it arrives as `any Error`.
///
/// Conform a new failure type where it is declared, never here — this file states the mechanism, not the mapping. A type used at more than one call site with more than one meaning (`CaptureBundleError`, read both from a caller's own bundle path and from a walk's read-back of the bundle its own runner just wrote) conforms to its more common meaning and is overridden at the one site that means something else, rather than split into two types.
public protocol UsageFailureClassifiable {
    var usageFailureKind: UsageFailureKind { get }
}

public extension UsageFailureKind {
    /// The kind `error` reports itself as, or `nil` for an error with no opinion — which a caller records as a site not yet mapped to a kind, rather than guesses at.
    static func of(_ error: Error) -> UsageFailureKind? {
        (error as? UsageFailureClassifiable)?.usageFailureKind
    }
}
