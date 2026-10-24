//
// Copyright © Agulhas Labs
//

import Foundation

/// The runner's word that the app is launched and requests are being polled for (`ready.json`).
public struct LiveSessionReady: Codable, Equatable, Sendable {
    /// The device, read from the runner's own process.
    public let device: CaptureManifest.Device
    /// The commit the runner was built from, as the host passed it; `nil` when the host could not tell.
    public let runnerCommit: String?
    /// When the runner started polling, by its own clock.
    public let readyAt: Date
    /// Lines the runner has for the start's answer: that it turned the device to match a landscape-only app (SimWalk#222). Absent from a runner that has none.
    public let notes: [String]?

    public init(device: CaptureManifest.Device, runnerCommit: String?, readyAt: Date, notes: [String]? = nil) {
        self.notes = notes
        self.device = device
        self.runnerCommit = runnerCommit
        self.readyAt = readyAt
    }
}
