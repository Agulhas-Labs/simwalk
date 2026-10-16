//
// Copyright © Agulhas Labs
//

import Darwin
import Foundation
import SimWalkCore

/// The setup a walk has made on a device and not yet handed back, on disk (SimWalk#63), and read back by the next walk on that device, setup or not (SimWalk#72, SimWalk#73).
///
/// A walk killed between its setup and its handback — SIGINT, SIGTERM, SIGKILL, an MCP server stopped mid-call — runs no handback, and Increase Contrast, a grant or the status bar stay changed. **The record is written before each change is made** (``DeviceSetup/apply(_:udid:bundleID:journal:run:)``) and removed only once the handback put everything back, so a killed walk leaves one naming every change it may have made, and whose process made it. A file per device, `<udid>.json`.
///
/// **A walk writes and removes only its own record**, told apart by the `token` in it. One another walk left is settled before this walk's first change (``claim(udid:run:forSetup:mayHandBack:)``): handed back when its process is gone, a refusal while it runs, moved aside and said when it does not read. A walk that makes no setup settles it too, before its runner (SimWalk#73), but is never refused by one whose walk still runs: it captures with the leftover in place and says so.
public struct DeviceSetupJournal: Sendable {
    /// `~/.simwalk/setup`, or a scratch directory in a test.
    public let directory: URL
    /// The process whose walk writes the records — this one, but for a test.
    private let pid: Int32
    /// What tells this walk's record from one another walk in the same process left — an MCP server runs its walks in-process, one after another.
    private let token: String
    /// What a record's pid is judged running by — alive, and started no later than the record was written (SimWalk#73).
    private let processes: any LiveSessionProcesses
    /// When a record is written, so a later walk can tell its pid from one reused since.
    private let now: @Sendable () -> Date

    public init(directory: URL, pid: Int32 = getpid(), token: String = UUID().uuidString, processes: any LiveSessionProcesses = LiveSessionSystemProcesses(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.pid = pid
        self.token = token
        self.processes = processes
        self.now = now
    }

    /// Beside a lease store — `~/.simwalk/setup` beside `~/.simwalk/leases`, and a test's scratch beside its own — so a walk handed a scratch lease store never writes the machine's.
    public static func beside(_ leases: LeaseStore) -> DeviceSetupJournal {
        DeviceSetupJournal(directory: leases.directory.deletingLastPathComponent().appendingPathComponent("setup", isDirectory: true))
    }

    /// Settles a record another walk left on `udid`, before this walk changes anything: `nil` when there is none.
    ///
    /// - A record whose process is gone, or is this one (an MCP server's earlier walk), is handed back as the walk that wrote it would have, judged by the same read-back, and removed once everything went back; a command that failed keeps it and refuses this walk, since writing this walk's record would lose it.
    /// - A record whose process is still running is another walk's that has not handed back: a refusal, naming the pid — unless `forSetup` is false (a walk that makes no setup, SimWalk#73), which is told so and leaves it where it is.
    /// - A record that does not read is moved aside, kept for a person to read, and said: nothing can hand back what it cannot read.
    ///
    /// `mayHandBack` false — a walk without a setup on a device it does not own — hands nothing back, since that changes device-wide state as a setup does: a gone walk's record, or an earlier walk's in this process, is left in place and said, and one that does not read is left where it is rather than moved aside (SimWalk#75), for a walk that owns the device to settle. `leaseLapsed` says the walk did own it, but its lease could not be renewed first; every caller says which.
    func claim(udid: String, run: (String, [String]) throws -> Shell.Result, forSetup: Bool = true, mayHandBack: Bool = true, leaseLapsed: Bool) throws -> Leftover? {
        sweepStaged()
        let url = url(for: udid)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let entry: Entry
        do {
            entry = try JSONDecoder().decode(Entry.self, from: Data(contentsOf: url))
        } catch {
            guard mayHandBack else { return .unreadableInPlace(path: url.path, reason: "\(error)") }
            let kept = directory.appendingPathComponent("\(udid).unreadable-\(token)").appendingPathExtension("json")
            do {
                try FileManager.default.moveItem(at: url, to: kept)
            } catch let moving {
                throw DeviceSetupError.leftoverRecord(path: url.path, reason: "it does not read as a setup record (\(error)), and it could not be moved aside to \(kept.path) (\(moving)), so this walk's own record cannot be written without losing it", handback: [])
            }
            return .unreadable(path: url.path, keptAt: kept.path, reason: "\(error)")
        }
        guard entry.token != token else { return nil }
        let thisProcess = entry.pid == pid
        let running = !thisProcess && isRunning(entry)
        if running, !forSetup {
            return .leftInPlace(entry, cause: .walkRunning, thisProcess: false)
        }
        guard !running else {
            throw DeviceSetupError.leftoverRecord(path: url.path, reason: "it is the setup record of pid \(entry.pid), which is still running and has not handed back \(entry.applied.parts.joined(separator: "; ")) — let it finish; if pid \(entry.pid) is no simwalk walk (a pid reused since), hand those back and delete the file", handback: [])
        }
        guard mayHandBack else { return .leftInPlace(entry, cause: leaseLapsed ? .leaseLapsed : .notOwned, thisProcess: thisProcess) }
        let handback = DeviceSetup.putBack(entry.applied, udid: udid, bundleID: entry.bundleID, run: run)
        guard handback.failed.isEmpty else {
            throw DeviceSetupError.leftoverRecord(path: url.path, reason: "it is the setup record of pid \(entry.pid), \(thisProcess ? "an earlier walk in this process" : "no longer running"), which never handed back \(entry.applied.parts.joined(separator: "; ")); handing it back failed, so the record is kept — run what is below, then delete the file", handback: handback.lines)
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw DeviceSetupError.notRecorded(path: url.path, reason: "the record pid \(entry.pid) left was handed back but could not be removed: \(error)", handback: handback.lines)
        }
        return .handedBack(entry, handback: handback, thisProcess: thisProcess, forSetup: forSetup)
    }

    /// Writes what the walk is about to have made on `udid`, whole or not at all, and never over a record this walk did not write; a failure refuses the change it was for.
    ///
    /// **This walk's first record is linked into place, never written over whatever is there** (SimWalk#73 item 6): written whole beside it, then `link(2)`, which refuses a name that exists as `O_EXCL` does — so a record another walk on the device wrote after this one looked is refused rather than lost, as ``LiveSessionClaim`` takes a claim. Only a record carrying this walk's token is replaced, atomically.
    func record(_ applied: DeviceSetup.Applied, udid: String, bundleID: String) throws {
        let url = url(for: udid)
        let data: Data
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            sweepStaged()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            data = try encoder.encode(Entry(udid: udid, bundleID: bundleID, pid: pid, token: token, applied: applied, recordedAt: now()))
            if entry(onDevice: udid)?.token == token {
                try data.write(to: url, options: .atomic)
                return
            }
        } catch {
            throw DeviceSetupError.notRecorded(path: url.path, reason: "\(error)", handback: [])
        }
        // Staged under a name that is not a record's, so one a crash leaves behind is never read as one.
        let staged = directory.appendingPathComponent(".\(udid).\(UUID().uuidString).staged")
        // Removed on every way out, a write that fails part-way included: it leaves a partial file under the name.
        defer { unlink(staged.path) }
        do {
            try data.write(to: staged, options: .withoutOverwriting)
        } catch {
            throw DeviceSetupError.notRecorded(path: url.path, reason: "\(error)", handback: [])
        }
        guard link(staged.path, url.path) == 0 else {
            let code = errno
            throw DeviceSetupError.notRecorded(path: url.path, reason: code == EEXIST ? "a record this walk did not write is there, and writing over it would lose it" : String(cString: strerror(code)), handback: [])
        }
    }

    /// How old a staged file must be before it is swept: a record is staged and linked in microseconds, so one this old is a crash's, never a walk's in flight.
    static let staleStagedAge: TimeInterval = 3600

    /// Removes the `.staged` files a crash left in the directory (SimWalk#76), older than ``staleStagedAge``; best effort, since a file that stays is only litter.
    private func sweepStaged() {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix(".") && name.hasSuffix(".staged") {
            let path = directory.appendingPathComponent(name).path
            guard let modified = (try? manager.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
                  now().timeIntervalSince(modified) > Self.staleStagedAge else { continue }
            unlink(path)
        }
    }

    /// The record on `udid`; `nil` when there is none or it does not read.
    public func entry(onDevice udid: String) -> Entry? {
        (try? Data(contentsOf: url(for: udid))).flatMap { try? JSONDecoder().decode(Entry.self, from: $0) }
    }

    /// Whether there is a record on `udid`, read or not: what a walk that makes no setup renews its lease for before settling it (SimWalk#75).
    public func hasRecord(onDevice udid: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: udid).path)
    }

    /// Removes the record on `udid` once its handback put everything back — only when this walk wrote it, so a walk refused before its first change leaves another walk's record where it was.
    func remove(udid: String) {
        guard entry(onDevice: udid)?.token == token else { return }
        try? FileManager.default.removeItem(at: url(for: udid))
    }

    /// Removes the record on `udid` — a clone `simwalk prune` just deleted, so nothing is left for a handback to put back — unless the walk that wrote it still runs (SimWalk#75).
    ///
    /// With `dryRun` it removes nothing. Only the record at `<udid>.json` is touched, and only when it reads: an unreadable one, and every `.unreadable-*` file kept beside it, is evidence and stays.
    public func prune(udid: String, dryRun: Bool) -> Pruned {
        guard let entry = entry(onDevice: udid) else { return .none }
        guard !isRunning(entry) else { return .kept(pid: entry.pid) }
        if !dryRun {
            do {
                try FileManager.default.removeItem(at: url(for: udid))
            } catch {
                return .notRemoved(reason: error.localizedDescription)
            }
        }
        return .removed
    }

    /// Every device whose record this journal holds under its own name — `<udid>.json`, not a staged file or an `.unreadable-*` copy kept beside one — whether or not it reads.
    public func recordedUDIDs() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { name in
            guard !name.hasPrefix("."), name.hasSuffix(".json") else { return nil }
            let udid = String(name.dropLast(".json".count))
            return udid.contains(".") ? nil : udid
        }.sorted()
    }

    func url(for udid: String) -> URL {
        directory.appendingPathComponent(udid).appendingPathExtension("json")
    }

    /// Whether the walk that wrote `entry` still runs: its pid alive, and not started after the record was written — a pid reused since is a stranger, whose record is handed back as a gone walk's is.
    ///
    /// **A start time that cannot be read counts as running here**, the opposite of a live session's rule (``LiveSessionProcesses/reuse(of:)``): wrongly handing back a running walk's grants or contrast mid-capture costs more than a qualification. A record from before `recordedAt` existed is judged by the pid alone. The second's allowance is the live session's.
    private func isRunning(_ entry: Entry) -> Bool {
        guard processes.isAlive(entry.pid) else { return false }
        guard let recordedAt = entry.recordedAt, let started = processes.startTime(of: entry.pid) else { return true }
        return started.timeIntervalSince(recordedAt) <= 1
    }
}

public extension DeviceSetupJournal {
    /// What `simwalk prune` did, would do, or declined to do with the record on a device whose clone it deleted.
    enum Pruned: Equatable, Sendable {
        /// There is no record that reads: none, or an unreadable one, which is left as it is.
        case none
        /// Removed — or, with `dryRun`, would be.
        case removed
        /// Left in place: the walk that wrote it, `pid`, still runs.
        case kept(pid: Int32)
        /// To be removed, but the removal failed, for `reason`; the record is still there.
        case notRemoved(reason: String)
    }

    /// One device's record: what was, or was about to be, made on it, for which app, by which process and walk.
    struct Entry: Codable, Equatable, Sendable {
        public let udid: String
        public let bundleID: String
        public let pid: Int32
        /// The walk that wrote it — the only one that may write over it or remove it.
        public let token: String
        public let applied: DeviceSetup.Applied
        /// When it was last written; `nil` in a record from before the field existed, whose pid is then judged by liveness alone.
        public var recordedAt: Date?
    }

    /// A record another walk left on the device, as this walk settled it before its own setup (SimWalk#72).
    enum Leftover: Equatable, Sendable {
        /// Its process gone, or this one: handed back, every command run — before this walk's setup, or before the runner of a walk that makes none.
        case handedBack(Entry, handback: DeviceSetup.Handback, thisProcess: Bool, forSetup: Bool)
        /// It did not read: moved aside to `keptAt`, nothing handed back.
        case unreadable(path: String, keptAt: String, reason: String)
        /// It did not read, and a walk that makes no setup on a device it does not own found it: left where it is, nothing handed back (SimWalk#75).
        case unreadableInPlace(path: String, reason: String)
        /// A walk that makes no setup found it and left it where it is (SimWalk#73), for the `cause` — and, when its walk is gone, whether that was an earlier walk in `thisProcess`.
        case leftInPlace(Entry, cause: InPlaceCause, thisProcess: Bool)

        /// What the answer and the manifest say of it.
        public var lines: [String] {
            switch self {
            case let .handedBack(entry, handback, thisProcess, forSetup):
                CaptureManifest.SetupRecord.leftoverLines(pid: entry.pid, thisProcess: thisProcess, bundleID: entry.bundleID, made: entry.applied.parts, handedBack: handback.restored, unconfirmed: handback.unconfirmed, before: forSetup ? "this walk's setup" : "this walk ran")
            case let .unreadable(path, keptAt, reason):
                CaptureManifest.SetupRecord.unreadableLeftoverLines(path: path, keptAt: keptAt, reason: reason)
            case let .unreadableInPlace(path, reason):
                ["⚠ setup leftover: \(path) does not read as a setup record (\(reason)), so what an earlier walk may have left on the device can neither be said nor handed back; left where it is, since this walk does not own the device — the next walk that does will move it aside"]
            case let .leftInPlace(entry, cause, thisProcess):
                ["⚠ setup leftover: pid \(entry.pid) (\(cause == .walkRunning ? "still running" : thisProcess ? "an earlier walk in this process" : "no longer running")) made \(entry.applied.parts.joined(separator: "; ")) for \(entry.bundleID) and has not handed it back; this walk captured with it in place, \(cause.reason)"]
            }
        }

        /// What it qualifies the walk's answer by: the device was not as this walk's setup found it until the leftover went back.
        public var qualification: String {
            switch self {
            case let .handedBack(_, _, _, forSetup):
                "a setup an earlier walk left on the device, handed back before \(forSetup ? "this one's" : "this walk ran")"
            case .unreadable:
                "a setup record an earlier walk left that does not read, kept"
            case .unreadableInPlace:
                "a setup record an earlier walk left that does not read, left in place"
            case let .leftInPlace(entry, cause, thisProcess):
                cause == .walkRunning ? "the device carries a setup pid \(entry.pid) made, a walk still running" : "the device carries a setup \(thisProcess ? "an earlier walk in this process" : "a gone walk") left, not handed back"
            }
        }
    }
}

public extension DeviceSetupJournal.Leftover {
    /// Why a record was left where it is.
    enum InPlaceCause: Equatable, Sendable {
        /// Its walk still runs, and the device is that walk's until it hands back.
        case walkRunning
        /// This walk never owned the device.
        case notOwned
        /// This walk owned the device, but its lease could not be renewed (lapsed, released, or the store unreadable) to hand the record back.
        case leaseLapsed

        /// Why this walk captured with the record in place, as the leftover line ends.
        var reason: String {
            switch self {
            case .walkRunning: "since the device is that walk's until it hands back"
            case .notOwned: "since it does not own the device to hand it back — the next walk that does will"
            case .leaseLapsed: "since its lease on the device could not be renewed to hand it back — the next walk that holds the lease will"
            }
        }
    }
}
