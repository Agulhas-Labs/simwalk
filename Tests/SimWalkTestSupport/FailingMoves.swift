//
// Copyright © Agulhas Labs
//

import Foundation

/// A file manager whose moves fail where a test says, the way a disk that fills or a volume that goes away fails a fold halfway through (SimWalk#26).
///
/// Every other operation is the real one, so a test sees exactly what a fold leaves on disk when one move goes wrong.
///
/// A namespace handing out an internal subclass rather than a public one: the override then carries no access modifier. A public override has to be spelled `public override` for SwiftFormat's configured `--modifierorder` and `override public` for SwiftLint's `modifier_order`, and no spelling passes both.
public struct FailingMoves {
    /// A file manager whose `moveItem` throws, touching nothing, whenever `failing` says so of the move asked for.
    public static func fileManager(failing: @escaping @Sendable (_ source: URL, _ destination: URL) -> Bool) -> FileManager {
        Manager(failing: failing, partway: false)
    }

    /// A file manager whose `moveItem` fails partway whenever `failing` says so, the way a move between two volumes does (the round-3 review): such a move is a copy and then a delete, so the destination holds a whole copy, the source has lost a file of it, and the move throws.
    ///
    /// Named apart from `fileManager(failing:)`, so a trailing closure picks one without a label.
    public static func partwayFileManager(failing: @escaping @Sendable (_ source: URL, _ destination: URL) -> Bool) -> FileManager {
        Manager(failing: failing, partway: true)
    }
}

extension FailingMoves {
    /// The file manager `fileManager(failing:)` and `partwayFileManager(failing:)` hand out.
    final class Manager: FileManager, @unchecked Sendable {
        private let failing: @Sendable (_ source: URL, _ destination: URL) -> Bool
        private let partway: Bool

        init(failing: @escaping @Sendable (_ source: URL, _ destination: URL) -> Bool, partway: Bool) {
            self.failing = failing
            self.partway = partway
            super.init()
        }

        override func moveItem(at source: URL, to destination: URL) throws {
            guard failing(source, destination) else {
                return try super.moveItem(at: source, to: destination)
            }
            if partway {
                try copyItem(at: source, to: destination)
                try deleteFirstFile(of: source)
            }
            throw CocoaError(.fileWriteOutOfSpace, userInfo: [NSFilePathErrorKey: destination.path])
        }

        /// The first file under `url` in path order, or `url` itself when it is a file — the part of the source a failed delete got through.
        private func deleteFirstFile(of url: URL) throws {
            guard isDirectory(url) else {
                return try removeItem(at: url)
            }
            let first = try subpathsOfDirectory(atPath: url.path).sorted().map { url.appendingPathComponent($0) }.first { !isDirectory($0) }
            if let first {
                try removeItem(at: first)
            }
        }

        private func isDirectory(_ url: URL) -> Bool {
            var isDirectory: ObjCBool = false
            return fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }
}
