//
// Copyright © Agulhas Labs
//

import Foundation

/// Empties the runner app's data container on a physical device (SimWalk#116).
///
/// `devicectl device copy to --source <empty directory> --destination Documents --remove-existing-content true` clears the **whole container** (Documents and Library), measured at 0.17 s; `--remove-existing-content` clears the domain, not the destination. So the wipe is constructible only from the runner's bundle id, from which it derives the container itself: a caller cannot point it at a walkbook's app.
public struct RunnerContainerWipe {
    public let udid: String
    /// The runner's own container (`<runner bundle id>.xctrunner`), derived in `init`.
    public let containerBundleID: String
    private let shell: Shell

    public init(udid: String, runnerBundleID: String?, shell: Shell = Shell()) {
        self.udid = udid
        containerBundleID = RunnerInvocation.deviceContainerBundleID(runnerBundleID: runnerBundleID)
        self.shell = shell
    }

    /// Never throws: a wipe that fails qualifies an answer and does not undo a walk.
    public func empty() -> Outcome {
        do {
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("simwalk-wipe-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            let result = try shell.run("/usr/bin/xcrun", [
                "devicectl", "device", "copy", "to",
                "--device", udid,
                "--domain-type", "appDataContainer",
                "--domain-identifier", containerBundleID,
                "--source", scratch.path,
                "--destination", "Documents",
                "--remove-existing-content", "true",
                "--quiet",
            ])
            guard result.succeeded else {
                return Outcome(emptied: false, line: "runner container not emptied: \(result.failureLine)")
            }
            return Outcome(emptied: true, line: "runner container emptied")
        } catch {
            return Outcome(emptied: false, line: "runner container not emptied: \(error)")
        }
    }
}

public extension RunnerContainerWipe {
    /// What the wipe did, as the line the answer carries.
    struct Outcome: Equatable, Sendable {
        public let emptied: Bool
        public let line: String
    }
}
