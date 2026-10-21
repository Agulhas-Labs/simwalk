//
// Copyright © Agulhas Labs
//

import Foundation

/// Where a ``JUnitReport`` lands: one atomic write, so a CI step polling the path sees the old file or the new one.
public struct JUnitFile {
    /// Writes `report` to `path`; the parent directory must exist, because a `--junit` path is checked before any work is done.
    public static func write(_ report: JUnitReport, to path: String) throws {
        try AtomicFileWrite.write(report.data(), to: URL(fileURLWithPath: path).standardizedFileURL)
    }

    /// Whether `path`'s parent directory exists — the up-front check, made before the run so a typo does not cost a walk.
    public static func parentExists(of path: String) -> Bool {
        guard !path.isEmpty else { return false }
        var isDirectory: ObjCBool = false
        let parent = URL(fileURLWithPath: path).standardizedFileURL.deletingLastPathComponent().path
        return FileManager.default.fileExists(atPath: parent, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

public extension JUnitFile {
    /// Whether `path` is an existing directory, which a report cannot replace.
    static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
