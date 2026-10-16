//
// Copyright © Agulhas Labs
//

import Foundation

/// Accumulates a child's two streams from the threads draining them.
final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = ""
    private var error = ""

    func append(_ text: String, isStandardError: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if isStandardError {
            error += text
        } else {
            out += text
        }
    }

    func standardOutput() -> String {
        lock.lock()
        defer { lock.unlock() }
        return out
    }

    func standardError() -> String {
        lock.lock()
        defer { lock.unlock() }
        return error
    }
}
