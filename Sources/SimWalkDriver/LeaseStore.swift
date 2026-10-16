//
// Copyright © Agulhas Labs
//

import Darwin
import Foundation

/// The machine's device leases: one file per leased UDID under `~/.simwalk/leases` (Brief §2.4).
///
/// **A lease is taken by linking a fully written temporary file to its path** — `link` fails where the path exists, as `O_EXCL` does — so of any number of acquisitions of one device exactly one creates it and the rest find it there, and no lease file is ever there without its bytes. Nothing else creates a lease file. **Every acquisition and every removal is made under one `flock`, and a removal only of the lease it read** — a release by its token, a reclaim of the stale lease it judged — so a reclaim can never remove a lease somebody created after it looked. **A lease that cloned its device leaves the store before its device is deleted** (`retire`): renamed under the lock to a tombstone that keeps every acquisition off the device until the delete is done.
public struct LeaseStore: Sendable {
    /// `~/.simwalk/leases`, or a scratch directory in a test.
    public let directory: URL
    private let isAlive: @Sendable (Int32) -> Bool
    /// Writes a lease's bytes into a descriptor, and says whether all of them went — the seam a test interrupts a write through.
    var writeBytes: @Sendable (Int32, Data) -> Bool = Self.writeAll
    /// Takes a tombstone's `flock` (`flock(2)`'s own arguments and answer) — the seam a test holds a copy of the descriptor through, as a child another thread is spawning does until its exec (SimWalk#71).
    var takeLock: @Sendable (Int32, Int32) -> Int32 = { flock($0, $1) }

    public init(directory: URL, isAlive: @escaping @Sendable (Int32) -> Bool = HolderProcess.isAlive) {
        self.directory = directory
        self.isAlive = isAlive
    }

    /// The machine's own leases — never moved by `SIMWALK_USAGE_LOG`, since a lease that a test or a review could not see would not keep it off a device.
    public static func standard() -> LeaseStore {
        LeaseStore(directory: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".simwalk", isDirectory: true)
            .appendingPathComponent("leases", isDirectory: true))
    }

    /// Takes the lease on `udid`, reclaiming one that has expired or whose holder is gone unless that lease cloned the device (`LeaseError.awaitingDeletion`: it is released instead); throws `LeaseError.held` naming the holder otherwise.
    public func acquire(
        udid: String,
        ttl: TimeInterval,
        holderPID: Int32,
        now: Date,
        createdDevice: Bool = false,
        clonedFrom: String? = nil,
        physicalDevice: Bool = false,
        token: String = UUID().uuidString
    ) throws -> DeviceLease {
        let granted = DeviceLease(token: token, holderPID: holderPID, createdAt: now, expiresAt: now.addingTimeInterval(ttl), createdDevice: createdDevice, clonedFrom: clonedFrom, physicalDevice: physicalDevice ? true : nil)
        let data = try Self.encoder.encode(granted)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw LeaseError.storeFailed(path: directory.path, reason: error.localizedDescription)
        }
        return try withLock {
            // A device whose clone lease is being released is on its way to `simctl delete`.
            guard tombstones(of: udid).isEmpty else {
                throw LeaseError.awaitingDeletion(udid: udid)
            }
            if try create(url(for: udid), with: data) {
                return granted
            }
            let existing = try lease(onDevice: udid)
            if let existing, isHeld(existing, now: now) {
                throw LeaseError.held(udid: udid, holderPID: existing.holderPID, expiresAt: existing.expiresAt)
            }
            // A lapsed lease that cloned its device is released, never taken over: a new lease would not know the clone was made, and nothing would ever delete it.
            if let existing, existing.createdDevice {
                throw LeaseError.awaitingDeletion(udid: udid)
            }
            if let existing {
                try removeLocked(udid: udid, token: existing.token)
            }
            if try create(url(for: udid), with: data) {
                return granted
            }
            let winner = try lease(onDevice: udid)
            throw LeaseError.held(udid: udid, holderPID: winner?.holderPID ?? 0, expiresAt: winner?.expiresAt ?? now)
        }
    }

    /// Whether `lease` still keeps others off its device: not expired, and its holder still running.
    public func isHeld(_ lease: DeviceLease, now: Date) -> Bool {
        lease.expiresAt > now && isAlive(lease.holderPID)
    }

    /// The lease on `udid`, `nil` when there is none; a file that does not decode is refused rather than read as free.
    public func lease(onDevice udid: String) throws -> DeviceLease? {
        let url = url(for: udid)
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        guard let lease = try? Self.decoder.decode(DeviceLease.self, from: data) else {
            throw LeaseError.unreadable(path: url.path)
        }
        return lease
    }

    /// Every lease on disk, by UDID, in UDID order; a file that does not decode is left out of this and still keeps its device from `held(now:)`.
    public func all() -> [Entry] {
        udids().compactMap { udid in
            (try? lease(onDevice: udid)).flatMap(\.self).map { Entry(udid: udid, lease: $0) }
        }
    }

    /// The UDIDs no walk may take without a token: every live lease, every lease file that cannot be read, every device a release is deleting, and every clone whose lease has lapsed — it awaits deletion (`simwalk prune`), and is never taken over.
    public func held(now: Date) -> [String: DeviceLease?] {
        var held: [String: DeviceLease?] = [:]
        for tombstone in allTombstones() {
            held[tombstone.entry.udid] = tombstone.entry.lease
        }
        for udid in udids() {
            do {
                if let lease = try lease(onDevice: udid), isHeld(lease, now: now) || lease.createdDevice {
                    held[udid] = lease
                }
            } catch {
                held[udid] = DeviceLease?.none
            }
        }
        return held
    }

    /// Extends the lease carrying `token` to `now + ttl`, under the store's lock, and never shortens it: the lease as it stands afterwards.
    ///
    /// **Only a lease that still keeps others off its device is renewed** — one that has expired, or whose holder has exited, is reclaimable by any session, so renewing it would protect nothing, and the refusal says which (`LeaseError.expired`, `.holderExited`). The renewed lease is written whole into a temporary file and renamed over the old one, so a reader sees one lease or the other and never a part of either.
    @discardableResult
    public func renew(token: String, ttl: TimeInterval, now: Date) throws -> DeviceLease {
        try withLock {
            guard let current = entry(token: token) else {
                throw LeaseError.noSuchLease
            }
            let lease = current.lease
            guard lease.expiresAt > now else {
                throw LeaseError.expired(udid: current.udid, expiresAt: lease.expiresAt)
            }
            guard isAlive(lease.holderPID) else {
                throw LeaseError.holderExited(udid: current.udid, holderPID: lease.holderPID)
            }
            let expiresAt = max(lease.expiresAt, now.addingTimeInterval(ttl))
            guard expiresAt > lease.expiresAt else { return lease }
            let renewed = DeviceLease(token: lease.token, holderPID: lease.holderPID, createdAt: lease.createdAt, expiresAt: expiresAt, createdDevice: lease.createdDevice, clonedFrom: lease.clonedFrom, physicalDevice: lease.physicalDevice)
            let url = url(for: current.udid)
            let failure = try placeTemporary(Self.encoder.encode(renewed), at: url) { rename($0, $1) }
            guard failure == 0 else {
                throw LeaseError.storeFailed(path: url.path, reason: String(cString: strerror(failure)))
            }
            return renewed
        }
    }

    /// The lease carrying `token`.
    public func entry(token: String) -> Entry? {
        all().first { $0.lease.token == token }
    }

    /// Removes the lease on `udid` if it still carries `token`, under the store's lock; whether it did.
    @discardableResult
    public func remove(udid: String, token: String) throws -> Bool {
        try withLock { try removeLocked(udid: udid, token: token) }
    }

    /// Takes the lease on `udid` out of the store if it still carries `token`, runs `release` on it, and removes it for good once `release` returns; `false`, with nothing touched and `release` not run, when the lease is no longer the one carrying `token`.
    ///
    /// The lease file is renamed, under the lock, to a tombstone (`<udid>.releasing.<token>`) that refuses every acquisition of the device (`LeaseError.awaitingDeletion`), so no lease can be taken on it while `release` — the `simctl` calls, seconds long — runs outside the lock. This process holds a `flock` on the tombstone throughout, which is how `finishAbandonedReleases` tells a release in progress from one a crash left. When `release` throws, the lease is put back where it was, so the release can be run again.
    public func retire(udid: String, token: String, release: (Entry) throws -> Void) throws -> Bool {
        let tombstone = directory.appendingPathComponent("\(udid)\(Self.tombstoneMarker)\(token)")
        let taken: (entry: Entry, descriptor: Int32)? = try withLock {
            guard let current = try? lease(onDevice: udid), current.token == token else { return nil }
            let descriptor: Int32
            do throws(LockFailure) {
                descriptor = try openLocked(url(for: udid), blocking: true)
            } catch {
                throw LeaseError.storeFailed(path: error.path, reason: error.reason)
            }
            guard rename(url(for: udid).path, tombstone.path) == 0 else {
                let reason = String(cString: strerror(errno))
                Self.unlockAndClose(descriptor)
                throw LeaseError.storeFailed(path: url(for: udid).path, reason: reason)
            }
            return (Entry(udid: udid, lease: current), descriptor)
        }
        guard let taken else { return false }
        // Closing the descriptor releases the tombstone's lock, after the tombstone is gone or the lease is back.
        defer { Self.unlockAndClose(taken.descriptor) }
        do {
            try release(taken.entry)
        } catch {
            try withLock {
                if link(tombstone.path, url(for: udid).path) == 0 {
                    unlink(tombstone.path)
                }
            }
            throw error
        }
        unlink(tombstone.path)
        return true
    }

    /// Finishes every release a process began and did not end — a tombstone whose `flock` no process holds, since a crash lets it go — handing each lease to `release` and removing its tombstone once `release` returns; with `dryRun`, only names them.
    ///
    /// A tombstone whose release is still running is left to it. One whose `release` throws stays, for the next prune.
    public func finishAbandonedReleases(dryRun: Bool, release: (Entry) throws -> Void) -> [(entry: Entry, failure: String?)] {
        allTombstones().compactMap { tombstone in
            let descriptor: Int32
            do throws(LockFailure) {
                descriptor = try openLocked(tombstone.url, blocking: false)
            } catch {
                // Held is a release still running; gone is one that finished between the listing and the lock. Anything else is said, errno and all (SimWalk#71).
                guard error.code != EWOULDBLOCK, error.code != ENOENT else { return nil }
                return (tombstone.entry, "its tombstone \(error.path) could not be locked to tell a crashed release from one still running: \(error.reason) — left for the next prune")
            }
            defer { Self.unlockAndClose(descriptor) }
            // The release that owned it may have finished between the listing and the lock.
            guard Self.isSameFile(descriptor, tombstone.url) else { return nil }
            guard !dryRun else { return (tombstone.entry, nil) }
            do {
                try release(tombstone.entry)
            } catch {
                return (tombstone.entry, String(describing: error))
            }
            unlink(tombstone.url.path)
            return (tombstone.entry, nil)
        }
    }

    /// Removes the temporary files a crash left in the store — `.<udid>.json.<uuid>.tmp`, older than `minimumAge` by `now`, so one a writer is still filling is left alone — under the lock; the count removed, or with `dryRun` the count that would be.
    ///
    /// Such a file is never read as a lease, so this only frees the space.
    public func sweepTemporaries(now: Date, minimumAge: TimeInterval = 60, dryRun: Bool) -> Int {
        (try? withLock {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            return names.filter { $0.hasPrefix(".") && $0.hasSuffix(".tmp") }.filter { name in
                let url = directory.appendingPathComponent(name)
                guard let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
                      now.timeIntervalSince(modified) > minimumAge else { return false }
                return dryRun || (try? FileManager.default.removeItem(at: url)) != nil
            }.count
        }) ?? 0
    }

    func url(for udid: String) -> URL {
        directory.appendingPathComponent("\(udid).\(Self.fileExtension)")
    }

    private static var fileExtension: String {
        "json"
    }

    /// Between a tombstone's UDID and its token; a tombstone's name never ends in the lease extension, so no lease read finds one.
    private static var tombstoneMarker: String {
        ".releasing."
    }

    /// Removes the lease on `udid` if it still carries `token`; the caller holds the lock.
    @discardableResult
    private func removeLocked(udid: String, token: String) throws -> Bool {
        guard (try? lease(onDevice: udid))??.token == token else { return false }
        do {
            try FileManager.default.removeItem(at: url(for: udid))
        } catch {
            throw LeaseError.storeFailed(path: url(for: udid).path, reason: error.localizedDescription)
        }
        return true
    }

    private func tombstones(of udid: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix("\(udid)\(Self.tombstoneMarker)") }
    }

    /// Every tombstone whose lease reads, by name.
    private func allTombstones() -> [Tombstone] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.sorted().compactMap { name in
            guard let marker = name.range(of: Self.tombstoneMarker) else { return nil }
            let url = directory.appendingPathComponent(name)
            guard let data = FileManager.default.contents(atPath: url.path), let lease = try? Self.decoder.decode(DeviceLease.self, from: data) else { return nil }
            return Tombstone(url: url, entry: Entry(udid: String(name[..<marker.lowerBound]), lease: lease))
        }
    }

    /// Opens `url` and takes its `flock`, waiting for it or not; the descriptor, released with ``unlockAndClose(_:)``.
    private func openLocked(_ url: URL, blocking: Bool) throws(LockFailure) -> Int32 {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw LockFailure(path: url.path, code: errno)
        }
        guard takeLock(descriptor, blocking ? LOCK_EX : LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            throw LockFailure(path: url.path, code: code)
        }
        return descriptor
    }

    /// Lets go of a tombstone's `flock` and closes its descriptor.
    ///
    /// **Unlocked first, never by the close alone** (SimWalk#71). A `flock` belongs to the open file, and a close releases it only once no descriptor refers to it — and a child any thread of this process is spawning holds a copy of every descriptor until its exec, `O_CLOEXEC` and `POSIX_SPAWN_CLOEXEC_DEFAULT` notwithstanding (measured on Darwin 27: a lock closed while another thread spawned was still held when re-taken at once, about once in 2,000 cycles; `LOCK_UN` first, never in 250,000). A lock outliving its close makes the next look at the tombstone — a prune's real run after its dry run — take a crash's release for one still running.
    private static func unlockAndClose(_ descriptor: Int32) {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    /// Whether `url` still names the file open at `descriptor`.
    private static func isSameFile(_ descriptor: Int32, _ url: URL) -> Bool {
        var open = stat()
        var named = stat()
        guard fstat(descriptor, &open) == 0, stat(url.path, &named) == 0 else { return false }
        return open.st_dev == named.st_dev && open.st_ino == named.st_ino
    }

    private func udids() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".\(Self.fileExtension)") }.map { String($0.dropLast(Self.fileExtension.count + 1)) }.sorted()
    }

    /// Writes the lease into a temporary file beside `url` and links it to `url`; `false` when `url` is already there.
    ///
    /// **`link` is the create**: it is atomic and fails when the path exists, so it keeps `O_EXCL`'s exclusivity, and a lease file is never seen, or left by a crash, without its bytes. The temporary file is unlinked whatever happens, and its name does not end in the lease extension, so one a crash leaves behind is never read as a lease.
    private func create(_ url: URL, with data: Data) throws -> Bool {
        let failure = try placeTemporary(data, at: url) { link($0, $1) }
        guard failure == 0 else {
            if failure == EEXIST {
                return false
            }
            throw LeaseError.storeFailed(path: url.path, reason: String(cString: strerror(failure)))
        }
        return true
    }

    /// Writes `data` whole into a temporary file beside `url` and puts it at `url` with `place` — `link` to create a lease, `rename` to replace one; the `errno` `place` failed with, or 0.
    ///
    /// The temporary file is unlinked whatever happens, and its name does not end in the lease extension, so one a crash leaves behind is never read as a lease.
    private func placeTemporary(_ data: Data, at url: URL, by place: (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32) throws -> Int32 {
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let descriptor = temporary.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_WRONLY | O_CREAT | O_EXCL, 0o644) } ?? -1
        }
        guard descriptor >= 0 else {
            throw LeaseError.storeFailed(path: temporary.path, reason: String(cString: strerror(errno)))
        }
        defer { _ = temporary.withUnsafeFileSystemRepresentation { $0.map { unlink($0) } } }
        let written = writeBytes(descriptor, data)
        let writeError = errno
        close(descriptor)
        guard written else {
            throw LeaseError.storeFailed(path: temporary.path, reason: String(cString: strerror(writeError)))
        }
        let placed = temporary.withUnsafeFileSystemRepresentation { from in
            url.withUnsafeFileSystemRepresentation { to in
                guard let from, let to else { return Int32(-1) }
                return place(from, to)
            }
        }
        return placed == 0 ? 0 : errno
    }

    /// Every byte of `data` into `descriptor`, however many `write` calls that takes.
    static func writeAll(_ descriptor: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(descriptor, buffer.baseAddress?.advanced(by: offset), buffer.count - offset)
                guard written > 0 else { return false }
                offset += written
            }
            return true
        }
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        let lockURL = directory.appendingPathComponent(".lock")
        let descriptor = lockURL.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_RDWR | O_CREAT | O_CLOEXEC, 0o644) } ?? -1
        }
        guard descriptor >= 0 else {
            throw LeaseError.storeFailed(path: lockURL.path, reason: String(cString: strerror(errno)))
        }
        // Unlocked before the close, never by the close alone (SimWalk#71, #76): a spawning child's copy of the descriptor would keep the lock held past it.
        defer { Self.unlockAndClose(descriptor) }
        _ = takeLock(descriptor, LOCK_EX)
        return try body()
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public extension LeaseStore {
    /// A lease and the device it is on.
    struct Entry: Equatable, Sendable {
        public let udid: String
        public let lease: DeviceLease
    }
}

extension LeaseStore {
    /// A lease taken out of the store for its device's deletion, and the file holding it.
    struct Tombstone {
        let url: URL
        let entry: Entry
    }

    /// A lock `openLocked` could not take — the file would not open, or its `flock` failed — and the `errno` that said why.
    struct LockFailure: Error {
        let path: String
        let code: Int32

        /// The errno's text and its number, which is what a report of a failure nobody expected needs to be evidence.
        var reason: String {
            "\(String(cString: strerror(code))) (errno \(code))"
        }
    }
}
