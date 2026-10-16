//
// Copyright © Agulhas Labs
//

import Foundation

/// What a live session's runner launches, written by the host before the runner starts (`launch.json`).
///
/// A file rather than more environment because a ``Walkbook/CaptureState`` is a structure, and the directory is already the channel both sides share.
public struct LiveSessionLaunch: Codable, Equatable, Sendable {
    /// The app the session drives.
    public let appBundleID: String
    /// The state the app is launched under, as a walk launches a state; `nil` launches it plain, on the device as it stands.
    public let state: Walkbook.CaptureState?

    public init(appBundleID: String, state: Walkbook.CaptureState?) {
        self.appBundleID = appBundleID
        self.state = state
    }
}
