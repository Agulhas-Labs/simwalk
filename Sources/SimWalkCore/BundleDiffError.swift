//
// Copyright © Agulhas Labs
//

/// Why a diff's crops could not be written where the caller asked.
///
/// Refused before anything is compared, on the rule `walk --output` follows: a directory already holding something would mix this diff's crops with an earlier one's, and a reader opening `progress-light-3.png` could not tell whose it was.
public enum BundleDiffError: Error, Equatable, CustomStringConvertible, UsageFailureClassifiable {
    /// The crops directory exists and holds something.
    case cropsDirectoryNotEmpty(path: String, entries: Int)
    /// The crops path is a file, or a directory this process cannot list.
    case cropsNotWritable(path: String, reason: String)

    public var description: String {
        switch self {
        case let .cropsDirectoryNotEmpty(path, entries):
            "\(path) already holds \(entries) item\(entries == 1 ? "" : "s") — crops are written to a new or empty directory, or an earlier diff's would be read as this one's; remove it or choose another path"
        case let .cropsNotWritable(path, reason):
            "cannot write crops at \(path): \(reason)"
        }
    }

    /// Both are a caller's argument.
    public var usageFailureKind: UsageFailureKind {
        .inputRefused
    }
}
