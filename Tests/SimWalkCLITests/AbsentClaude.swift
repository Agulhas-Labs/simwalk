//
// Copyright © Agulhas Labs
//

import Fieldwork

/// A machine with no `claude` on PATH: every run answers `nil`, as the real runner does, so a registration already in the config is left standing.
struct AbsentClaude: ClaudeMcpRunner {
    func run(_: [String]) throws -> Subprocess.Output? {
        nil
    }
}
