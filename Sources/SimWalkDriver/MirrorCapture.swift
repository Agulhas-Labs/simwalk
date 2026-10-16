//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Captures the iPhone Mirroring window by its window id, so an overlapping window is never in the picture (Brief §8 "The observation").
public struct MirrorCapture {
    private let shell: Shell

    public init(shell: Shell = Shell()) {
        self.shell = shell
    }

    /// Writes `window` as a PNG at `file` (`screencapture -o -x -l <id>`: no shadow, no sound).
    ///
    /// A file already there is removed first, so a capture that wrote nothing is never read as the last one. Refused on a non-zero exit, and on a zero one that left no image — which is what a missing Screen Recording grant looks like.
    public func capture(window: MirrorWindowFrame, to file: URL, clearance _: MirrorFocus.Clearance) throws {
        try? FileManager.default.removeItem(at: file)
        let result = try shell.run("/usr/sbin/screencapture", ["-o", "-x", "-l", String(window.windowID), file.path], timeout: 15)
        guard result.succeeded else {
            throw MirrorControlError.captureFailed(reason: result.failureLine)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else {
            throw MirrorControlError.captureMissing(path: file.path)
        }
    }
}
