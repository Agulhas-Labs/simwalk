//
// Copyright © Agulhas Labs
//

import Foundation

/// Captures the server's diagnostics, which are the only place it may say anything that is not JSON-RPC.
///
/// A class behind a lock because the server hands its logger out as a `@Sendable` closure and calls it from whatever context the failure happened on.
final class LogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var lines: [String] {
        lock.withLock { recorded }
    }

    var record: @Sendable (String) -> Void {
        { [self] line in
            lock.withLock { recorded.append(line) }
        }
    }
}
