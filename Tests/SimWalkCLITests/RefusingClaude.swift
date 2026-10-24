//
// Copyright © Agulhas Labs
//

import Fieldwork

/// A `claude` that is there and refuses every run, as a `claude mcp remove` that fails does.
struct RefusingClaude: ClaudeMcpRunner {
    func run(_: [String]) throws -> Subprocess.Output? {
        Subprocess.Output(succeeded: false, standardOutput: "", standardError: "refused for the test")
    }
}
