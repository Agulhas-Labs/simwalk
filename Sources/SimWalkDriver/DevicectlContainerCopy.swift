//
// Copyright © Agulhas Labs
//

import Foundation

/// ``DeviceContainerCopying`` over `xcrun devicectl device copy from`, reading the runner app's `appDataContainer`.
///
/// `containerBundleID` is the installed runner's own (`RunnerInvocation.deviceContainerBundleID(runnerBundleID:)`): a UI test runner is an app of its own, and its container is where it can write.
public struct DevicectlContainerCopy: DeviceContainerCopying {
    public let udid: String
    public let containerBundleID: String
    private let shell: Shell

    public init(udid: String, containerBundleID: String, shell: Shell = Shell()) {
        self.udid = udid
        self.containerBundleID = containerBundleID
        self.shell = shell
    }

    public func copy(source: String, to destination: URL) throws {
        let result = try shell.run("/usr/bin/xcrun", [
            "devicectl", "device", "copy", "from",
            "--device", udid,
            "--domain-type", "appDataContainer",
            "--domain-identifier", containerBundleID,
            "--source", source,
            "--destination", destination.path,
            "--quiet",
        ])
        guard result.succeeded else {
            let stderr = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw DeviceTransferError.copyFailed(reason: stderr.isEmpty ? result.failureLine : stderr)
        }
    }
}
