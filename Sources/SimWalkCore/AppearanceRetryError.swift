//
// Copyright © Agulhas Labs
//

import Foundation

/// Why a second attempt at a walk's screens could not be folded into its bundle (SimWalk#26).
///
/// Every case but the last is found before the bundle is touched: a fold that cannot be made leaves the first attempt's bundle exactly as the runner wrote it. The last is a fold that failed on disk and could not be undone, and it says where the first attempt is.
public enum AppearanceRetryError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The second attempt's manifest attributes itself to something else than the first's — another app, build or device — so its records answer a different walk.
    case notTheSameWalk(field: String, first: String, retry: String)
    /// The second attempt recorded other screens than the ones it was sent to walk again.
    case retryRecordedOtherScreens(expected: [String], recorded: [String])
    /// A fold failed on disk, and putting the first attempt back failed too: its manifest and the screen directories not yet put back are still set aside at `setAside` — the only copy of them, which the caller must keep (the round-2 review).
    case foldNotUndone(setAside: String, reason: String, undoReason: String)

    public var description: String {
        switch self {
        case let .notTheSameWalk(field, first, retry):
            "the second attempt's \(field) is \(retry) where the first attempt's is \(first) — its records answer a different walk, so the first attempt stands"
        case let .retryRecordedOtherScreens(expected, recorded):
            "the second attempt recorded [\(recorded.joined(separator: ", "))] where it was sent to walk [\(expected.joined(separator: ", "))] again — the first attempt stands"
        case let .foldNotUndone(setAside, reason, undoReason):
            "folding the second attempt in failed (\(reason)), and putting the first attempt back failed too (\(undoReason)) — its manifest and the screen directories not yet put back are set aside at \(setAside); move them back into the bundle, over the screen directories of the same name, to recover it"
        }
    }
}
