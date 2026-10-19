//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimWalkDriver

/// The simulator a walk or dry run runs on, with everything it holds there: the lease it runs under and its claim (SimWalk#128).
///
/// **The claim is taken whatever lease the walk runs under**: a session's handback exempts the `--lease` token of the session it hands back, and a walk's ``WalkClaim`` under no token. A claim that cannot be written refuses the walk and releases a lease it took, so a refusal here leaves nothing held.
struct HeldDevice {
    let simulator: Simulator
    let lease: WalkLease
    let claim: WalkClaim

    /// Takes the device `walk` names (`--device`, `--lease`, or any free one), its lease and its claim, before anything touches the device.
    static func take(for walk: WalkCommand, shell: Shell, leases: LeaseStore, now: Date) throws -> HeldDevice {
        let (simulator, lease) = try leased(device: walk.device, token: walk.lease, shell: shell, leases: leases, now: now)
        do {
            return try HeldDevice(simulator: simulator, lease: lease, claim: LeaseError.mapping { try WalkClaim.take(udid: simulator.udid, in: leases) })
        } catch {
            lease.release()
            throw error
        }
    }

    /// Releases the claim, and the lease when the walk took it (``WalkLease/release()`` leaves a handed-in one be).
    func release() {
        claim.release()
        lease.release()
    }

    /// The device a walk runs on, with the lease it runs under.
    ///
    /// With a `token`, the leased device, its lease renewed for ``WalkLease/ttl`` — a lease that can no longer be renewed (expired, its holder gone) keeps nobody off the device, so the walk is refused before it touches it. Without, a lease this process takes itself on the device `device` names, or on any free one (``WalkLease/take(_:among:store:holderPID:now:)``); only `simctl list` has run when either refuses.
    private static func leased(device: String?, token: String?, shell: Shell, leases: LeaseStore, now: Date) throws -> (simulator: Simulator, lease: WalkLease) {
        guard let token else {
            return try WalkLease.take(device, among: Simulator.available(shell: shell), store: leases, holderPID: ProcessInfo.processInfo.processIdentifier, now: now)
        }
        let simulator = try Simulator.resolve(device, lease: token, leases: leases, now: now, shell: shell)
        _ = try LeaseError.mapping { try leases.renew(token: token, ttl: WalkLease.ttl, now: now) }
        return (simulator, WalkLease(store: leases, udid: simulator.udid, token: token, taken: false))
    }
}
