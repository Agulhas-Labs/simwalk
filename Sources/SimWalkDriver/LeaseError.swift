//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimWalkCore

/// Why a lease could not be taken, used or released.
public enum LeaseError: Error, Equatable, CustomStringConvertible {
    /// The device carries a live lease the caller did not present.
    case held(udid: String, holderPID: Int32, expiresAt: Date)
    /// A lease file that does not decode — never reclaimed, since what cannot be read cannot be judged free.
    case unreadable(path: String)
    case noSuchLease
    case expired(udid: String, expiresAt: Date)
    /// A lease whose holder has exited: reclaimable by anyone, so renewing it would keep nobody off the device.
    case holderExited(udid: String, holderPID: Int32)
    /// Every device a choice could fall on is leased.
    case noUnleasedDevice(runtime: String)
    /// No shut-down device among those a lease could fall on is free — a name, or a runtime when nothing was named — and a booted one is leased only when named by UDID.
    case noShutDownDevice(among: String)
    case cloneSourceBooted(udid: String)
    /// A device whose lease is being released, or a clone whose lease has lapsed, which is released — the clone deleted — and never leased again.
    case awaitingDeletion(udid: String)
    /// A created device that could not be shut down or deleted; the lease is kept so a release can be run again.
    case deviceNotDeleted(udid: String, command: String, reason: String)
    /// A device the lease found shut down that could not be shut down again on release; the lease is kept so a release can be run again.
    case deviceNotShutDown(udid: String, reason: String)
    case storeFailed(path: String, reason: String)
    /// A token presented to a physical-device walk whose lease is on a simulator.
    case notPhysicalLease(udid: String)

    public var description: String {
        switch self {
        case let .held(udid, pid, expiresAt):
            "\(udid) is leased by pid \(pid) until \(Self.time(expiresAt)) — take a device of your own (`simwalk lease acquire`), or pass that lease's token with --lease; nothing on the device was touched"
        case let .unreadable(path):
            "the lease at \(path) cannot be read, so the device is treated as held — remove the file if no walk holds it"
        case .noSuchLease:
            "no lease carries that token — it was released, or reclaimed after it expired; `simwalk lease list` shows what is held"
        case let .expired(udid, expiresAt):
            "the lease on \(udid) expired at \(Self.time(expiresAt)) — release it and acquire again"
        case let .holderExited(udid, pid):
            "the lease on \(udid) lived as long as pid \(pid), which has exited, so any session may reclaim it and renewing it would keep nobody off the device — release it and acquire again"
        case let .noUnleasedDevice(runtime):
            "every available \(runtime) simulator is leased — release one (`simwalk lease list`), or clone one (`simwalk lease acquire --clone-from <udid>`)"
        case let .noShutDownDevice(among):
            "no shut-down \(among) simulator is free to lease, and a booted one may be in use by a session that takes no leases, so it is leased only when named by UDID — `simwalk lease acquire --device <udid>` for a booted device that is yours, `simwalk lease acquire --clone-from <udid>` to clone a shut-down one, or `simwalk lease list` to see what is held"
        case let .cloneSourceBooted(udid):
            "\(udid) is booted and simctl clones only a device that is shut down — shut it down first (xcrun simctl shutdown \(udid)) if it is yours to stop"
        case let .awaitingDeletion(udid):
            "the lease on \(udid) is being released, or is a clone's that has lapsed, which is deleted rather than leased again — a release a crash left is finished by `simwalk prune`; take another device (`simwalk lease acquire`); nothing on the device was touched"
        case let .deviceNotDeleted(udid, command, reason):
            "\(command) failed: \(reason) — the lease on \(udid) is kept; release it again, or run xcrun simctl shutdown \(udid) && xcrun simctl delete \(udid)"
        case let .deviceNotShutDown(udid, reason):
            "simctl shutdown \(udid) failed: \(reason) — the lease found the device shut down, so it is kept until the device is shut down again; release it again, or run xcrun simctl shutdown \(udid) and then release it"
        case let .storeFailed(path, reason):
            "the lease store at \(path) could not be written: \(reason)"
        case let .notPhysicalLease(udid):
            "that lease is on \(udid), which is not a physical device — `device walk` walks a phone leased with `simwalk lease acquire --physical <udid>`; a simulator lease is walked with `simwalk walk --lease`; nothing was touched"
        }
    }

    /// The same refusal, as SimWalk words it, for a failure the Fieldwork lease store reports.
    init(_ error: LeaseStoreError) {
        switch error {
        case let .storeFailed(path, reason): self = .storeFailed(path: path, reason: reason)
        case let .awaitingDeletion(udid): self = .awaitingDeletion(udid: udid)
        case let .held(udid, holderPID, expiresAt): self = .held(udid: udid, holderPID: holderPID, expiresAt: expiresAt)
        case let .unreadable(path): self = .unreadable(path: path)
        case .noSuchLease: self = .noSuchLease
        case let .expired(udid, expiresAt): self = .expired(udid: udid, expiresAt: expiresAt)
        case let .holderExited(udid, holderPID): self = .holderExited(udid: udid, holderPID: holderPID)
        }
    }

    /// Runs a call into the lease store, rethrowing what the store refuses as a `LeaseError` and letting every other error through.
    public static func mapping<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as LeaseStoreError {
            throw LeaseError(error)
        }
    }

    /// Takes a walk claim on `udid`, refusing as the lease store itself does when the claim cannot be written.
    ///
    /// `WalkClaim.take` throws what `FileManager` and `Data.write` throw — Cocoa errors, never a `LeaseStoreError` — so `mapping` alone let them through to be logged under a call site's default kind, `runnerFailed`, for a refusal that is the machine's store and not the runner. They become `storeFailed` naming the lease store's directory, which classifies as `toolError`.
    public static func takingClaim(udid: String, in leases: LeaseStore) throws -> WalkClaim {
        do {
            return try mapping { try WalkClaim.take(udid: udid, in: leases) }
        } catch let error as LeaseError {
            throw error
        } catch {
            throw LeaseError.storeFailed(path: leases.directory.path, reason: "a walk claim for \(udid) could not be written under it: \(error.localizedDescription)")
        }
    }

    /// A lease's expiry as its refusal prints it: the subject of the line, not its provenance.
    public static func time(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}

extension LeaseError: UsageFailureClassifiable {
    /// A lease somebody else holds, a token that holds nothing and a booted clone source are all the caller's argument meeting the machine as it is; a store or a device that would not do what was asked is the machine.
    public var usageFailureKind: UsageFailureKind {
        switch self {
        case .held, .unreadable, .noSuchLease, .expired, .holderExited, .noUnleasedDevice, .noShutDownDevice, .cloneSourceBooted, .awaitingDeletion, .notPhysicalLease: .inputRefused
        case .deviceNotDeleted, .deviceNotShutDown: .deviceLeftBad
        case .storeFailed: .toolError
        }
    }
}
