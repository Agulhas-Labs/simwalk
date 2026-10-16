//
// Copyright © Agulhas Labs
//

import Foundation

/// Why a physical iPhone cannot be walked, named before any build is started (SimWalk#116).
///
/// Each case names the prerequisite that failed and what to do about it; nothing was built, installed or run on the device.
public enum PhysicalDeviceError: Error, Equatable, CustomStringConvertible {
    /// No signing team was given: xcodebuild cannot sign a runner for a physical device without one.
    case noTeam
    /// A `devicectl` answer that did not run, did not decode, or lacked a field the check needs — never assumed to mean "fine".
    case unreadable(command: String, reason: String)
    /// No physical device carries this UDID; `present` is every physical UDID `devicectl` did list.
    case notFound(udid: String, present: [String])
    case notPaired(udid: String, state: String)
    case notConnected(udid: String, state: String)
    /// Developer Mode is not enabled; `reported` is what `devicectl` said, verbatim in shape.
    case developerModeOff(udid: String, reported: String)
    case locked(udid: String)
    /// `devicectl device install app` failed; `reason` is its own error.
    case installFailed(path: String, udid: String, reason: String)

    public var description: String {
        switch self {
        case .noTeam:
            "no signing team given — pass --team <TEAM> (a ten-character Apple team ID); xcodebuild cannot sign the runner for a physical device without one, and nothing was run"
        case let .unreadable(command, reason):
            "`\(command)` could not be read (\(reason)) — a prerequisite that cannot be read is treated as unmet; run the command by hand to see why"
        case let .notFound(udid, present):
            "no physical device \(udid) — \(present.isEmpty ? "devicectl lists no physical device; connect the iPhone and unlock it" : "physical devices present: \(present.joined(separator: ", "))")"
        case let .notPaired(udid, state):
            "\(udid) is not paired with this Mac (pairing state: \(state)) — trust this Mac on the iPhone, or run `xcrun devicectl manage pair --device \(udid)`"
        case let .notConnected(udid, state):
            "\(udid) is not connected (connection state: \(state)) — connect it by cable or put it on the same network, then unlock it"
        case let .developerModeOff(udid, reported):
            "Developer Mode is not enabled on \(udid) (devicectl reported \(reported)) — enable it in Settings › Privacy & Security › Developer Mode; the iPhone restarts"
        case let .installFailed(path, udid, reason):
            "installing \(path) on \(udid) failed — devicectl said: \(reason)"
        case let .locked(udid):
            "\(udid) is locked — unlock it and keep it unlocked; a locked iPhone makes xcodebuild wait about 2.5 minutes on \"Unlock iPhone to Continue\" before it fails"
        }
    }
}
