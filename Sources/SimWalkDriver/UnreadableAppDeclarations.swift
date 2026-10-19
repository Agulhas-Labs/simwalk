//
// Copyright © Agulhas Labs
//

/// Why an installed app's declarations could not be read.
public struct UnreadableAppDeclarations: Error, Equatable, Sendable {
    /// The file that failed and what failed, as `<path>: <what failed>`.
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }
}
