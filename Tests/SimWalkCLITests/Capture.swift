//
// Copyright © Agulhas Labs
//

import Foundation

/// Collects what a command printed on each stream from the `@Sendable` closures it is given.
final class Capture: @unchecked Sendable {
    private let lock = NSLock()
    private var outLines: [String] = []
    private var errLines: [String] = []

    var stdout: [String] {
        lock.withLock { outLines }
    }

    var stderr: [String] {
        lock.withLock { errLines }
    }

    func out(_ text: String) {
        lock.withLock { outLines.append(text) }
    }

    func err(_ text: String) {
        lock.withLock { errLines.append(text) }
    }
}
