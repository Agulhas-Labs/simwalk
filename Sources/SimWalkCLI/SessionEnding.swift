//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Ends a session at most once, whichever asks first — the verb on its way out, or a SIGINT's cancel on the signal queue — and holds the other until it is done, so the process is not ended mid-handback.
final class SessionEnding: @unchecked Sendable {
    private let lock = NSLock()
    private var ended = false
    private let end: () throws -> Answer

    init(_ end: @escaping () throws -> Answer) {
        self.end = end
    }

    /// The end's answer, the first time; `nil` once the session has been ended.
    func once() throws -> Answer? {
        try lock.withLock {
            guard !ended else { return nil }
            ended = true
            return try end()
        }
    }
}
