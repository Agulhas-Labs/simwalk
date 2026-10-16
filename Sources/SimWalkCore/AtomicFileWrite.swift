//
// Copyright © Agulhas Labs
//

import Foundation

/// Replaces a file whole: the bytes go to a temporary file in the **same directory**, which `rename(2)` then moves over the target, so a reader polling the target sees the old file or the new one and never a torn one (`Docs/SIMWALK-PROGRESS.md` §3).
///
/// The same directory is what makes the rename atomic — a temporary elsewhere may be on another volume, where a "move" is a copy. The temporary is dot-prefixed and uniquely named, so two writers never share one, and it is removed on every way a write can fail, so nothing is left beside the target.
struct AtomicFileWrite {
    /// Writes `data` to `url`, creating its directory when missing.
    static func write(_ data: Data, to url: URL) throws {
        let files = FileManager.default
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staged = temporaryURL(beside: url)
        do {
            try data.write(to: staged)
        } catch {
            try? files.removeItem(at: staged)
            throw error
        }
        guard rename(staged.path, url.path) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            try? files.removeItem(at: staged)
            throw POSIXError(code)
        }
    }

    /// A name for the staged copy of `url` that no other write shares.
    static func temporaryURL(beside url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
    }
}
