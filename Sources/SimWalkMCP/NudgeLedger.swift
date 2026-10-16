//
// Copyright © Agulhas Labs
//

import CryptoKit
import Foundation
import SimWalkCore

/// What the hand-driving nudge remembers of the calls it refused, so its promise holds: **the identical re-run goes through** (SimWalk#12).
///
/// The promise is sift's, and so is the rule that keeps it honest: a refusal is not made unless its record was written, since a refusal that cannot be kept is a promise broken silently — and a context that has watched the escape hatch fail once has no reason to believe the next thing the hook says. So ``refuses(context:call:)`` answers `false`, and the call goes through, whenever the record does not land.
///
/// **One file per refused call, under one directory per context**, named for a hash of the call. A write never rewrites another call's record, so two calls a context makes at once cannot lose each other's, and the context's refusal count is its directory's listing.
///
/// **Brief, on purpose.** A record lasts ``memory``: long enough for the re-run it promises, short enough that a context working by hand an hour later hears the nudge again. A context hears the nudge at most once per ``memory`` and **never on its first hand-driving call** (SimWalk#110): a lone one-off capture is legitimate (SimWalk#12), and refusing it cost a turn in a large context for nothing. The first call goes through and is remembered by a marker file beside the records; the next *distinct* call is refused once, which is what a hand-tapped loop of screenshots still hears at its second capture; then the ``cap`` of one keeps the context quiet for the rest of the window — it has been told, and the tool does not get to argue.
public struct NudgeLedger: Sendable {
    /// How long a refusal is remembered, both as the licence for its re-run and toward the ``cap``.
    public static let memory: TimeInterval = 30 * 60

    /// Refusals one context hears within ``memory`` before the nudge goes quiet for it: one, since a context that has been told once and chosen otherwise is not told again (SimWalk#110).
    public static let cap = 1

    /// The prefix of the marker that a context's first hand-driving call went through: `seen-<hash of the call>`, per call so the seen call's own re-run is known for what it is.
    ///
    /// Not a refusal record: a record's name is bare hex, this one carries the prefix, and ``refuses(context:call:)`` counts only records toward the ``cap``.
    private static var seenPrefix: String {
        "seen-"
    }

    /// The directory holding one directory of records per context.
    public let directory: URL

    private let now: @Sendable () -> Date

    public init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.now = now
    }

    /// Beside `log`, as the call slips are: a test's scratch log keeps the nudge's records in scratch too.
    public init(beside log: UsageLog, now: @escaping @Sendable () -> Date = { Date() }) {
        self.init(directory: log.directory.appendingPathComponent("nudges", isDirectory: true), now: now)
    }

    /// Whether to refuse `call` in `context` — and, where the answer is `true`, the refusal is already on record.
    ///
    /// `false` for a context's first call within ``memory`` (remembered, not refused), for the re-run of a call refused within ``memory``, for a context that has already heard ``cap`` refusals within it, for a context id that is not plainly a name, and whenever the record cannot be written.
    public func refuses(context: String, call: String) -> Bool {
        guard Self.isContextName(context) else { return false }
        prune()
        // The check-then-write below is one decision: two hooks racing would each see no refusal and both write one, past the ``cap``. A lock across processes (flock, since each call is its own hook process) makes it one at a time; where it cannot be had, the call goes through, as it does whenever the record cannot be kept.
        return withLock { decide(context: context, call: call) } ?? false
    }
}

private extension NudgeLedger {
    /// Runs `body` holding an exclusive lock on a file beside the context directories (not inside one, where it would count as a record); `nil` where the lock cannot be taken.
    func withLock<T>(_ body: () -> T) -> T? {
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else { return nil }
        let descriptor = open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { return nil }
        defer { flock(descriptor, LOCK_UN) }
        return body()
    }

    func decide(context: String, call: String) -> Bool {
        let contextDirectory = directory.appendingPathComponent(context, isDirectory: true)
        let record = contextDirectory.appendingPathComponent(Self.recordName(for: call))
        guard !FileManager.default.fileExists(atPath: record.path) else { return false }
        let seenName = Self.seenPrefix + Self.recordName(for: call)
        let listing = (try? FileManager.default.contentsOfDirectory(atPath: contextDirectory.path)) ?? []
        // The call this context's first one was is not a distinct call: its re-run goes through, as any re-run does.
        guard !listing.contains(seenName) else { return false }
        let heard = listing.filter { !$0.hasPrefix(Self.seenPrefix) }
        guard heard.count < Self.cap else { return false }
        do {
            try FileManager.default.createDirectory(at: contextDirectory, withIntermediateDirectories: true)
            // A context's first hand-driving call is let through and only remembered; a refusal on record means it has been seen already.
            if heard.isEmpty, !listing.contains(where: { $0.hasPrefix(Self.seenPrefix) }) {
                try Data(call.utf8).write(to: contextDirectory.appendingPathComponent(seenName), options: .atomic)
                return false
            }
            try Data(call.utf8).write(to: record, options: .atomic)
        } catch {
            return false
        }
        return true
    }
}

private extension NudgeLedger {
    /// A call's record name: a hash of the call, since the call is a command line and the name is a path.
    static func recordName(for call: String) -> String {
        SHA256.hash(data: Data(call.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Whether a context id is plainly a name, for the reason a slip's session must be: it arrives in a payload and becomes a path.
    static func isContextName(_ context: String) -> Bool {
        !context.isEmpty && context.count <= 256
            && context.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// Forgets every record and seen marker past ``memory``, and the context directories that leaves empty — only ever what can no longer license a re-run or count toward the cap.
    func prune() {
        let cutoff = now().addingTimeInterval(-Self.memory)
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let contexts = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter(Self.isContextName)
        for context in contexts {
            let contextDirectory = directory.appendingPathComponent(context, isDirectory: true)
            let records = (try? FileManager.default.contentsOfDirectory(at: contextDirectory, includingPropertiesForKeys: keys)) ?? []
            for record in records {
                let modified = try? record.resourceValues(forKeys: Set(keys)).contentModificationDate
                guard let modified, modified < cutoff else { continue }
                try? FileManager.default.removeItem(at: record)
            }
            // `rmdir` refuses a directory with anything in it, so a record written meanwhile keeps its directory.
            rmdir(contextDirectory.path)
        }
    }
}
