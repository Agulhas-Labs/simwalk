//
// Copyright © Agulhas Labs
//

import Foundation

/// The lease a walk runs under: the one it was handed (`--lease`), or one it took itself on the device it resolved (Brief §2.4).
///
/// **A walk that names no lease still holds its device.** Resolving a device and then walking it without a lease left the device free for the length of the walk: another session's `lease acquire` could take a device this walk was about to boot, settle and set up. Taking the lease *is* the choice — `take` acquires each candidate in turn and walks the first one it wins — so two walks starting together cannot fall on one device, where choosing from a snapshot of the store and acquiring afterwards would let both choose it.
public struct WalkLease: Sendable {
    public let store: LeaseStore
    public let udid: String
    public let token: String
    /// Whether the walk took this lease itself, so it is the walk's to release; a lease handed in with `--lease` outlives the walk and is its holder's.
    public let taken: Bool

    public init(store: LeaseStore, udid: String, token: String, taken: Bool) {
        self.store = store
        self.udid = udid
        self.token = token
        self.taken = taken
    }

    /// How long a walk's lease holds from its last renewal: longer than a walk runs between two renewals, short enough that a walk killed outright frees its device within the half hour.
    public static var ttl: TimeInterval {
        30 * 60
    }

    /// Takes the device a walk should run on and a lease on it: among the devices `requested` names (a name or UDID; every device when nothing is named), booted ones before shut-down ones — booting a second device while one sits ready is a surprise — acquiring each until one is won.
    ///
    /// A named device with none of its candidates free is refused with the first refusal, which names the holder; nothing named and nothing free is `LeaseError.noUnleasedDevice`. A store that cannot be written is thrown at once rather than read as a busy device. Nothing here runs a command: the devices were listed by the caller, and a lease file is all that is written.
    public static func take(_ requested: String?, among devices: [Simulator], store: LeaseStore, holderPID: Int32, now: Date) throws -> (simulator: Simulator, lease: WalkLease) {
        guard !devices.isEmpty else {
            throw SimulatorError.noDevices
        }
        var pool = devices
        if let requested {
            pool = devices.filter { $0.udid == requested || $0.name == requested }
            guard !pool.isEmpty else {
                throw SimulatorError.noSuchDevice(requested: requested, available: devices.map(\.name))
            }
        }
        let candidates = pool.filter(\.isBooted) + pool.filter { !$0.isBooted }
        var refusal: LeaseError?
        for candidate in candidates {
            do {
                let lease = try store.acquire(udid: candidate.udid, ttl: ttl, holderPID: holderPID, now: now)
                return (candidate, WalkLease(store: store, udid: candidate.udid, token: lease.token, taken: true))
            } catch let error as LeaseError {
                if case .storeFailed = error {
                    throw error
                }
                refusal = refusal ?? error
            }
        }
        guard requested != nil, let refusal else {
            throw LeaseError.noUnleasedDevice(runtime: "iOS")
        }
        throw refusal
    }

    /// Takes the lease on a physical iPhone for a walk that named only its UDID: held by `holderPID` for `ttl`, the walk's to release.
    ///
    /// Taken before any `devicectl` call, reads included, so a phone leased by someone else is refused (`LeaseError.held`, naming the holder and expiry) with nothing run on it. The store's exclusive create is the whole guarantee that two walks started together on one phone give one winner.
    public static func takePhysical(udid: String, store: LeaseStore, holderPID: Int32, now: Date) throws -> WalkLease {
        let lease = try store.acquire(udid: udid, ttl: ttl, holderPID: holderPID, now: now, physicalDevice: true)
        return WalkLease(store: store, udid: udid, token: lease.token, taken: true)
    }

    /// The lease a physical-device walk was handed (`--lease`), left to its holder: `noSuchLease` for a token that holds nothing, `notPhysicalLease` for one on a simulator.
    public static func presentedPhysical(token: String, store: LeaseStore) throws -> WalkLease {
        guard let entry = store.entry(token: token) else {
            throw LeaseError.noSuchLease
        }
        guard entry.lease.physicalDevice == true else {
            throw LeaseError.notPhysicalLease(udid: entry.udid)
        }
        return WalkLease(store: store, udid: entry.udid, token: token, taken: false)
    }

    /// ``renew(now:)``, thrown: the refusal a walk makes before it changes anything on the device.
    public func requireRenewed(now: Date) throws {
        try store.renew(token: token, ttl: Self.ttl, now: now)
    }

    /// Extends the lease by `ttl` from `now`: `nil` when it holds, else why it could not be renewed — expired, its holder gone, or no longer in the store.
    public func renew(now: Date) -> String? {
        do {
            try store.renew(token: token, ttl: Self.ttl, now: now)
            return nil
        } catch {
            return String(describing: error)
        }
    }

    /// Removes a lease the walk took itself, by its token, so a lease somebody has since taken over is never removed; a `--lease` lease is left to its holder.
    ///
    /// A removal that fails leaves the lease to lapse on its own — at `ttl`, or when its holder exits — which is what a walk killed before this ran leaves too.
    public func release() {
        guard taken else { return }
        _ = try? store.remove(udid: udid, token: token)
    }
}
