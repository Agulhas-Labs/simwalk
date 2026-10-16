//
// Copyright © Agulhas Labs
//

import Foundation

/// Why the usage log could not be read at all — as distinct from its being absent, which is an answer rather than a failure.
///
/// The two were one case, and the collapse ran the wrong way: a log the reader could not open reported "no calls recorded yet" and exited 0, which is the tool telling a caller that a machine running it daily has never run it. A file that is not there and a file that will not open are different facts, and only the first of them is a report.
public enum UsageLogReadError: Error, Equatable, CustomStringConvertible {
    /// The path exists and its bytes could not be read: a permission change, a directory where a file belongs, a volume that went away.
    case unreadable(path: String, reason: String)

    public var description: String {
        switch self {
        case let .unreadable(path, reason):
            "\(path): \(reason)"
        }
    }
}
