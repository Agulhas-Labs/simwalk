//
// Copyright © Agulhas Labs
//

import Foundation

/// Captures what a command wrote, and to which stream.
///
/// A class so the closures handed to `TimedCall` mutate one recorder rather than copies of it — which stream a line went to is the assertion, so the two must not be able to drift apart.
final class StreamRecorder {
    private(set) var out: [String] = []
    private(set) var err: [String] = []

    func emit(_ text: String) {
        out.append(text)
    }

    func emitError(_ text: String) {
        err.append(text)
    }
}
