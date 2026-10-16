//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Uninstalls the runner app from a physical device (`simwalk device clean`, SimWalk#116).
///
/// Constructible only from the runner's bundle id, so it can never remove a walkbook's app. A runner that is not installed is an outcome, not a refusal.
public struct RunnerAppUninstall {
    public let udid: String
    public let appBundleID: String
    private let shell: Shell

    public init(udid: String, runnerBundleID: String?, shell: Shell = Shell()) {
        self.udid = udid
        appBundleID = RunnerInvocation.deviceContainerBundleID(runnerBundleID: runnerBundleID)
        self.shell = shell
    }

    public func run() throws -> Outcome {
        guard try isInstalled() else { return .notInstalled(bundleID: appBundleID) }
        let result = try shell.run("/usr/bin/xcrun", ["devicectl", "device", "uninstall", "app", "--device", udid, appBundleID])
        guard result.succeeded else {
            throw Failure(description: "devicectl could not uninstall \(appBundleID): \(result.failureLine)")
        }
        return .removed(bundleID: appBundleID)
    }

    /// `devicectl device info apps --bundle-id` answers success with an empty list for an app that is not there.
    private func isInstalled() throws -> Bool {
        let result = try shell.run("/usr/bin/xcrun", ["devicectl", "device", "info", "apps", "--device", udid, "--bundle-id", appBundleID, "--json-output", "-", "--quiet"])
        guard result.succeeded else {
            throw Failure(description: "devicectl could not read whether \(appBundleID) is installed: \(result.failureLine)")
        }
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any],
            let apps = (object["result"] as? [String: Any])?["apps"] as? [Any]
        else {
            throw Failure(description: "devicectl's list of installed apps for \(appBundleID) could not be read")
        }
        return !apps.isEmpty
    }
}

public extension RunnerAppUninstall {
    enum Outcome: Equatable, Sendable {
        case removed(bundleID: String)
        case notInstalled(bundleID: String)

        public var line: String {
            switch self {
            case let .removed(bundleID): "removed \(bundleID)"
            case let .notInstalled(bundleID): "\(bundleID) is not installed"
            }
        }
    }

    struct Failure: Error, CustomStringConvertible, UsageFailureClassifiable {
        public let description: String
        public var usageFailureKind: UsageFailureKind {
            .setupFailed
        }
    }
}
