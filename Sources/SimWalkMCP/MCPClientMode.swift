//
// Copyright © Agulhas Labs
//

/// How a server answers `walk`, chosen from the client's name: Claude Code gets one call answered when the walk ends, every other client a call bounded by a budget.
public enum MCPClientMode: Sendable, Equatable {
    case blocking
    case bounded

    /// The one client that is blocking; renaming it switches it to bounded, which is why a test pins its `tools/list` bytes.
    static var blockingClientName: String {
        "claude-code"
    }

    /// A client that sends no `clientInfo` is bounded.
    init(clientName: String?) {
        self = clientName == Self.blockingClientName ? .blocking : .bounded
    }
}
