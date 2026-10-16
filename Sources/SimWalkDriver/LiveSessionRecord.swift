//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// The host's record of one live session (`session.json`): what `read`, `end` and `list` need to find the runner and hand the device back.
///
/// **Host-only.** The runner never reads it — what the runner needs is `launch.json` — so a field here is a promise between host commands, never across the runner boundary, and ``LiveSessionStore`` is the only writer.
public struct LiveSessionRecord: Codable, Equatable, Sendable {
    public let id: String
    /// The `xcodebuild` process the session started, which leads its own process group.
    public let pid: Int32
    public let udid: String
    /// The app the session drives.
    public let app: String
    public let startedAt: Date
    /// The device's appearance as `start` found it, before the runner ran — what `end` puts back; `nil` when it could not be read.
    ///
    /// Held here because the handback runs in a later process than the one that read it, and a launch state that set the other appearance would otherwise be left on the device.
    public let foundAppearance: Walkbook.Theme?
    /// Where a physical device's runner listens and what its session holds; `nil` on a simulator.
    ///
    /// Optional, so a record written before devices had sessions still reads, and a simulator's record is written byte for byte as before: the synthesized coding skips an absent key both ways.
    public let device: DeviceEndpoint?
    /// The lease a simulator session was started under (`--lease`); `nil` when it was started by UDID, and in a record written before this field.
    ///
    /// Kept so the handback can tell the lease its own caller still holds from a stranger's: that lease is the session's caller, not another holder of the device. Optional, so older records still read and a session started by UDID is written byte for byte as before.
    public let leaseToken: String?

    public init(id: String, pid: Int32, udid: String, app: String, startedAt: Date, foundAppearance: Walkbook.Theme?, device: DeviceEndpoint? = nil, leaseToken: String? = nil) {
        self.id = id
        self.pid = pid
        self.udid = udid
        self.app = app
        self.startedAt = startedAt
        self.foundAppearance = foundAppearance
        self.device = device
        self.leaseToken = leaseToken
    }
}

public extension LiveSessionRecord {
    /// A device session's endpoint and holdings (Brief, "Live sessions on a physical device", rulings 7–8): the tunnel address read once at start, the port drawn for the session, what the runner was built under, and the phone's lease.
    ///
    /// **Never the token**: it is kept in the session directory's `token` file, mode 0600, alone.
    struct DeviceEndpoint: Codable, Equatable, Sendable {
        /// The tunnel address the runner bound, as `start` read it; a later read that differs is a new tunnel.
        ///
        /// Empty in the record `start` writes at the spawn, until the runner has answered on one.
        public let address: String
        public let port: UInt16
        public let team: String
        /// The runner's bundle identifier when it was overridden, `nil` for the project's own: it names the container `end` empties.
        public let runnerBundleID: String?
        /// The phone's lease, renewed by every session command.
        public let leaseToken: String
        /// Whether the session took the lease itself (`--device`), so `end` releases it; a presented `--lease` is left to its holder.
        public let leaseTaken: Bool
        /// The phone's appearance as `start` read it through devicectl, before the runner ran — what `end` hands back (ruling 9); `nil` when it could not be read.
        ///
        /// The whole reading, not only ``LiveSessionRecord/foundAppearance``'s theme: the handback compares the text size too, as `device walk`'s does.
        public let appearance: PhysicalDeviceAppearance?

        public init(address: String, port: UInt16, team: String, runnerBundleID: String?, leaseToken: String, leaseTaken: Bool, appearance: PhysicalDeviceAppearance?) {
            self.address = address
            self.port = port
            self.team = team
            self.runnerBundleID = runnerBundleID
            self.leaseToken = leaseToken
            self.leaseTaken = leaseTaken
            self.appearance = appearance
        }
    }
}

public extension LiveSessionRecord.DeviceEndpoint {
    /// Where the runner keeps its session files in its own container — `bind.json` arriving, `exit.json` written — as a `devicectl device copy` path.
    static var containerSessionPath: String {
        "Documents/SimWalkSession"
    }
}
