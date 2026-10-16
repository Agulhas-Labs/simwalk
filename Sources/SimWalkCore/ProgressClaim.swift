//
// Copyright © Agulhas Labs
//

import Foundation

/// A run's hold on its progress and result files (`Docs/SIMWALK-PROGRESS.md` §1): while it is held, no other run writes either file.
///
/// Two runs share a session id when they share a `CLAUDE_CODE_SESSION_ID` — an MCP walk and a CLI walk from the same session's shell — or when neither has one and both fall back to `default`. Each used to write the same `<session>.json`, the later run's writes landing in the middle of the earlier one's (SimWalk#83).
///
/// **The first run alive keeps the session's own name; a later one takes the next free slot.** A claim is a non-blocking `flock(2)` on `<session>.lock`, then `<session>.2.lock` and on, held until this object goes away. A reader that knows only the session id — a mod polling `<session>.json` — still finds the run it expects whenever one walk is alive, the common case; a run in a later slot is found through its answer's `result:` line and its `resultPath`. Slots are reused rather than keyed by pid, so the directory holds a few files per session rather than a pair for every run ever made.
///
/// **A live session starts at slot 2** (``take(session:in:firstSlot:sharedWithChild:)``'s `firstSlot`), so the session's own name stays a walk's: a session holds its slot for its whole life, up to its idle timeout after its last request, and a walk in that time would otherwise land in `<session>.2.json` while `<session>.json` showed an idle session (SimWalk#83).
///
/// The system drops a claim when its holder dies, so a run killed outright never wedges its slot. A lock that cannot be taken at all — a directory that cannot be written, a filesystem without `flock` — leaves the run on the slot it was trying, unclaimed, as every run was before: progress never fails a walk.
public final class ProgressClaim: @unchecked Sendable {
    /// The run's progress file.
    public let progressURL: URL
    /// The run's result file.
    public let resultURL: URL
    /// The locked descriptor, or `-1` when no lock could be taken.
    private let descriptor: Int32
    /// Whether a child process is handed the lock and keeps it after this object goes away — a live session's `xcodebuild`, whose life is the session's (SimWalk#83).
    private let sharedWithChild: Bool
    private let lock = NSLock()
    /// Whether a child was spawned holding the descriptor (``markHandedOver()``): only then is the lock left to it.
    private var handedOver = false

    private init(session: String?, slot: Int, in directory: URL, descriptor: Int32, sharedWithChild: Bool) {
        progressURL = ProgressLocation.progressURL(session: session, slot: slot, in: directory)
        resultURL = ProgressLocation.resultURL(session: session, slot: slot, in: directory)
        self.descriptor = descriptor
        self.sharedWithChild = sharedWithChild
    }

    deinit {
        guard descriptor >= 0 else { return }
        // Unlocked before the close, as `ExclusiveFileLock` does: a child mid-spawn holds a copy of the descriptor until its exec (SimWalk#71).
        // Not once a child holds the lock: a `flock` belongs to the open file, so `LOCK_UN` here would end the child's hold too, and the close alone leaves it with the child.
        // A shared claim no child inherited — a start refused, or failed, before its spawn — is unlocked like any other (SimWalk#83).
        if !lock.withLock({ handedOver }) {
            flock(descriptor, LOCK_UN)
        }
        close(descriptor)
    }

    /// The descriptor a child process inherits to keep the claim for as long as it lives; `nil` when the claim was not taken to be shared, or no lock could be taken.
    public var descriptorForChild: Int32? {
        sharedWithChild && descriptor >= 0 ? descriptor : nil
    }

    /// Records that a child was spawned holding ``descriptorForChild``, whose lock this object then only closes, never unlocks.
    ///
    /// Does nothing for a claim not taken to be shared.
    public func markHandedOver() {
        lock.withLock { handedOver = sharedWithChild }
    }

    /// Claims the first slot from `firstSlot` on that no other live run holds for `session` under `directory`.
    ///
    /// `firstSlot` is 1, the session's own name, for a walk, and 2 for a live session, which leaves the session's own name to walks (SimWalk#83).
    ///
    /// `sharedWithChild` takes a claim whose lock a child is handed (``descriptorForChild``) and keeps once this object is gone: once ``markHandedOver()`` says a child holds it, it is never unlocked here, only closed.
    public static func take(session: String?, in directory: URL, firstSlot: Int = 1, sharedWithChild: Bool = false) -> ProgressClaim {
        try? FileManager.default.createDirectory(at: ProgressLocation.progressDirectory(in: directory), withIntermediateDirectories: true)
        var slot = firstSlot
        while true {
            let descriptor = open(ProgressLocation.claimURL(session: session, slot: slot, in: directory).path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else {
                return ProgressClaim(session: session, slot: slot, in: directory, descriptor: -1, sharedWithChild: sharedWithChild)
            }
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                return ProgressClaim(session: session, slot: slot, in: directory, descriptor: descriptor, sharedWithChild: sharedWithChild)
            }
            let held = errno == EWOULDBLOCK
            close(descriptor)
            guard held else {
                return ProgressClaim(session: session, slot: slot, in: directory, descriptor: -1, sharedWithChild: sharedWithChild)
            }
            slot += 1
        }
    }
}
