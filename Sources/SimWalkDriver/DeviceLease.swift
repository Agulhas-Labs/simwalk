//
// Copyright © Agulhas Labs
//

import Foundation

/// One device's lease, as `~/.simwalk/leases/<udid>.json` holds it: who holds it, until when, and whether the lease made the device (Brief §2.4).
///
/// The token is the capability — a walk that presents it may use the device and reboot it — so it is written here and printed once, to the caller that acquired it, and never listed.
public struct DeviceLease: Codable, Equatable, Sendable {
    /// What the holder presents to walk the device (`--lease`) and to release it.
    public let token: String
    /// The process the lease lives as long as; once it is gone the lease is reclaimable.
    public let holderPID: Int32
    public let createdAt: Date
    /// After this the lease is reclaimable, and `simwalk prune` releases it.
    public let expiresAt: Date
    /// Whether the lease made the device (`--clone-from`) — the only case in which releasing it deletes the device.
    public let createdDevice: Bool
    /// The device it was cloned from, when it was.
    public let clonedFrom: String?
    /// Whether the lease is on a paired physical iPhone (`--physical`); absent in a lease written before the phone could be leased, which is a simulator's.
    public let physicalDevice: Bool?

    public init(token: String, holderPID: Int32, createdAt: Date, expiresAt: Date, createdDevice: Bool, clonedFrom: String?, physicalDevice: Bool? = nil) {
        self.token = token
        self.holderPID = holderPID
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.createdDevice = createdDevice
        self.clonedFrom = clonedFrom
        self.physicalDevice = physicalDevice
    }
}
