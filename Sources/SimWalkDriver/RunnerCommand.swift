//
// Copyright © Agulhas Labs
//

import Foundation

/// A runner command line, built but not run: what a live session spawns in the background rather than waits on.
public struct RunnerCommand: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    /// Added to the host's own environment — the `TEST_RUNNER_`-prefixed inputs.
    public let environment: [String: String]
    /// A descriptor the process inherits beside its standard three — a live session's progress claim (`ProgressClaim.descriptorForChild`), held for as long as the runner lives (SimWalk#83); `nil` for none.
    public let inheritedDescriptor: Int32?

    public init(executable: String, arguments: [String], environment: [String: String], inheritedDescriptor: Int32? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.inheritedDescriptor = inheritedDescriptor
    }
}
