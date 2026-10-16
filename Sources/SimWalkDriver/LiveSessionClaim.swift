//
// Copyright © Agulhas Labs
//

import Darwin
import Foundation
import SimWalkCore

/// One `session start`'s hold on a device, from before its build and settle until its `session.json` is written.
///
/// **The one-session check alone cannot keep two starts apart**: the record it looks for is written only once the runner is spawned, after a build and perhaps a settle, so a second start in that window finds nothing — and its settle reboots the first one's device, or two runners end up on it. A claim is a file created exclusively — linked into place, which fails on an existing name as `O_EXCL` does — in the store's `.claims` directory, named for the device, holding the claimant's pid; the second start fails to create it and is refused before it builds or settles anything.
///
/// **A claim whose claimant has died is reclaimed**, since a start killed mid-way cannot release its own. Reading the claim, judging its claimant, removing it and creating it afresh are several steps, and a compare-then-remove is not one of them: a second start could pass the compare, lose the race to a first that has already removed and re-created the claim, and then remove *that* — leaving both holding it. So the whole of `take` runs under an ``ExclusiveFileLock`` on a lock file beside the claim, which the system releases when its holder dies, so a start killed mid-take cannot wedge the next.
public struct LiveSessionClaim: Sendable {
    public let file: URL
    /// What this claim wrote — the claimant's pid and a token of its own — so a release never removes somebody else's claim.
    private let contents: String

    /// Takes the claim on `udid`, reclaiming one whose claimant is no longer alive.
    ///
    /// - Throws: ``LiveSessionHostError/startInProgress(udid:holder:)`` while a live claimant holds it.
    public static func take(udid: String, in store: LiveSessionStore, holder: Int32, isAlive: (Int32) -> Bool) throws -> LiveSessionClaim {
        let file = store.claim(udid: udid)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try ExclusiveFileLock(file: file.appendingPathExtension("lock")).withLock {
            try takeLocked(file: file, udid: udid, holder: holder, isAlive: isAlive)
        }
    }

    /// `take`'s body, run under the claim's lock.
    private static func takeLocked(file: URL, udid: String, holder: Int32, isAlive: (Int32) -> Bool) throws -> LiveSessionClaim {
        let contents = "\(holder) \(UUID().uuidString)\n"
        if try create(file, contents) {
            return LiveSessionClaim(file: file, contents: contents)
        }
        let found = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let claimant = Self.claimant(in: found)
        if let claimant, isAlive(claimant) {
            throw LiveSessionHostError.startInProgress(udid: udid, holder: claimant)
        }
        if (try? String(contentsOf: file, encoding: .utf8)) == found {
            try? FileManager.default.removeItem(at: file)
        }
        guard try create(file, contents) else {
            throw LiveSessionHostError.startInProgress(udid: udid, holder: claimant ?? 0)
        }
        return LiveSessionClaim(file: file, contents: contents)
    }

    /// Whether a live `session start` holds the claim on `udid` — building, settling, or rebooting the device — judged by the claimant's pid as `take` judges it.
    public static func isHeld(udid: String, in store: LiveSessionStore, isAlive: (Int32) -> Bool) -> Bool {
        let found = (try? String(contentsOf: store.claim(udid: udid), encoding: .utf8)) ?? ""
        return claimant(in: found).map(isAlive) ?? false
    }

    /// Every device a live `session start` holds a claim on, whether or not any session record names it (SimWalk#128): a start's record comes only after its claim.
    ///
    /// The `.claims` directory also holds each claim's `.lock` file and the `.`-prefixed files `create` stages before linking; neither is a claim.
    public static func heldDevices(in store: LiveSessionStore, isAlive: (Int32) -> Bool) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: store.claimsDirectory.path)) ?? []
        return Set(names.filter { !$0.hasPrefix(".") && !$0.hasSuffix(".lock") }.filter { isHeld(udid: $0, in: store, isAlive: isAlive) })
    }

    /// The pid a claim's contents name first; `nil` for contents that name none.
    private static func claimant(in contents: String) -> Int32? {
        contents.split(separator: " ").first.flatMap { Int32($0) }
    }

    /// Removes the claim, when it is still this one's.
    public func release() {
        guard (try? String(contentsOf: file, encoding: .utf8)) == contents else { return }
        try? FileManager.default.removeItem(at: file)
    }

    /// Creates `file` holding `contents` only when it does not exist; whether it did not.
    ///
    /// Written whole beside it first and then linked into place — `link(2)` refuses an existing name as `O_EXCL` does — so no reader ever finds the claim empty and takes it for one whose claimant cannot be named.
    private static func create(_ file: URL, _ contents: String) throws -> Bool {
        let staged = file.deletingLastPathComponent().appendingPathComponent(".\(file.lastPathComponent).\(UUID().uuidString)")
        try Data(contents.utf8).write(to: staged, options: .withoutOverwriting)
        defer { unlink(staged.path) }
        guard link(staged.path, file.path) == 0 else {
            guard errno == EEXIST else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path, NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)])
            }
            return false
        }
        return true
    }
}
