//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Renders this session's simwalk segment for a Claude Code status line.
///
/// **The saving leads, because it is the only figure here that means anything on its own.** A walk stands in for screenshots a reader would otherwise have had to look at, and that is what the line is for — the call count says the tool was used, which is a different and much weaker claim. Both are omitted when they are zero, and the whole segment is omitted when the session never called: silence is the right output for a session that never touched an app, and a status line is one line of screen shared with everything else.
///
/// Scanning is incremental because this runs on every assistant message against transcripts that reach tens of megabytes. Each transcript keeps its own byte offset and running counts beside the usage log, so a normal render parses only what was appended since the last one; transcripts are append-only, which is what makes that sound, and a file that has shrunk is taken as replaced and rescanned.
///
/// A session is more than the file Claude Code hands over: subagents write their own transcripts beside it, and a walk driven by a subagent is still this session's walk. They are counted here.
public struct StatuslineReport {
    private let cacheDirectory: URL

    /// The usage log the saving is priced from — beside the cache directory by default, and named separately so a test can put one where it owns it.
    private let usageLogURL: URL

    public init(cacheDirectory: URL, usageLogURL: URL? = nil) {
        self.cacheDirectory = cacheDirectory
        self.usageLogURL = usageLogURL ?? cacheDirectory.deletingLastPathComponent().appendingPathComponent("usage.jsonl")
    }

    /// The standard location, beside the usage log — the one `SIMWALK_USAGE_LOG` names where it is set, which need not be called `usage.jsonl`.
    public static func standard() -> StatuslineReport {
        StatuslineReport(cacheDirectory: SimWalkPaths.statuslineCacheDirectory, usageLogURL: UsageLog.standard().fileURL)
    }

    /// The segment for `transcriptPath`, or `nil` when the session has made no calls at all — or the status line is hidden.
    ///
    /// **The one exception to silence is a session that could have walked and has not** (SimWalk#12): where `workingDirectory` is served by a walkbook, no calls reads `0 walks · walkbook here`, because going around the tool is otherwise invisible. Checked with ``RepositoryWalkbooks/exist(from:)``, the same "loads as a walkbook" test the hook offers by (SimWalk#37 item 4) — a `*.json` that does not load is not offered by either.
    public func segment(transcriptPath: String, workingDirectory: String? = nil) -> String? {
        guard !StatuslineVisibility(cacheDirectory: cacheDirectory).isHidden else { return nil }
        let (tally, usage) = measure(transcriptPath: transcriptPath)
        guard tally.calls > 0 else {
            guard let workingDirectory, RepositoryWalkbooks.exist(from: workingDirectory) else { return nil }
            return "\(SimWalkPaths.binaryName) 0 walks · walkbook here"
        }

        var parts: [String] = []
        // An estimate, marked as one, at the constants the answers themselves were priced with — and a
        // floor, so it reads worst exactly where the tool is doing most.
        if usage.tokensSaved > 0 {
            parts.append("\(TokenEstimate.short(usage.tokensSaved)) saved")
        }
        parts.append(tally.counted)
        // Shown because they are otherwise invisible: a session whose walks all fell over, or were all
        // refused, is not a session using the tool, and the count alone cannot tell those apart. The two
        // words mean what `simwalk usage` means by them — failed is the tool, refused is a caller's own
        // argument — so one never stands in for the other, and a zero part is left off.
        if usage.failures > 0 {
            parts.append("\(usage.failures) failed")
        }
        if usage.refusals > 0 {
            parts.append("\(usage.refusals) refused")
        }
        return "\(SimWalkPaths.binaryName) " + parts.joined(separator: " · ")
    }

    /// The session's counts and what its calls saved — one pass, because both are cached in the same state and both are read on every render.
    func measure(transcriptPath: String) -> (tally: SessionTally, usage: SessionUsage) {
        var state = loadState(for: transcriptPath)
        var changed = false
        let paths = [transcriptPath] + subagentTranscripts(of: transcriptPath)

        // A transcript that has gone away must take its counts with it, or a deleted subagent keeps
        // contributing to the session's count forever.
        if state.entries.keys.contains(where: { !paths.contains($0) }) {
            state.entries = state.entries.filter { paths.contains($0.key) }
            changed = true
        }

        for path in paths {
            var entry = state.entries[path] ?? State.Entry()
            guard scan(path: path, into: &entry) else { continue }
            state.entries[path] = entry
            changed = true
        }

        let usage = SessionUsage.scanning(usageLogURL, after: state.usage, session: Self.session(of: transcriptPath))
        if usage != state.usage {
            state.usage = usage
            changed = true
        }

        if changed {
            save(state, for: transcriptPath)
        }
        return (state.entries.values.reduce(into: SessionTally()) { $0 += $1.tally }, usage)
    }

    /// The session a transcript belongs to: Claude Code names the file after it, and gives the same id to the MCP server in its environment.
    public static func session(of transcriptPath: String) -> String {
        URL(fileURLWithPath: transcriptPath).deletingPathExtension().lastPathComponent
    }

    /// The subagent transcripts belonging to a session.
    ///
    /// Claude Code writes them to `<session>/subagents/*.jsonl`, a directory named after the session transcript beside it. Each is scanned with its own offset, because each is its own append-only file.
    func subagentTranscripts(of transcriptPath: String) -> [String] {
        let directory = URL(fileURLWithPath: transcriptPath)
            .deletingPathExtension()
            .appendingPathComponent("subagents", isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { $0.pathExtension == "jsonl" }.map(\.path).sorted()
    }
}

private extension StatuslineReport {
    /// Reads what has been appended to one transcript, reporting whether anything was.
    func scan(path: String, into entry: inout State.Entry) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return false }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        // A shrunken file is a different file under the same name — a rotated or rewritten transcript — so
        // the offset is meaningless and the counts through it with it.
        var reset = false
        if size < entry.offset {
            entry = State.Entry()
            reset = true
        }
        // The reset is itself worth saving even when there is nothing yet to read: a transcript truncated to
        // zero would otherwise keep its old counts, since this returns before the state is written back.
        guard size > entry.offset else { return reset }

        try? handle.seek(toOffset: entry.offset)
        guard let appended = try? handle.readToEnd(), !appended.isEmpty else { return false }

        // Resume from the last complete line only: the writer may be mid-line, and half a JSON object parses
        // as nothing and would be silently lost once the offset moved past it.
        guard let lastNewline = appended.lastIndex(of: 0x0A) else { return false }
        let complete = appended[appended.startIndex ... lastNewline]

        for line in complete.split(separator: 0x0A, omittingEmptySubsequences: true) {
            TranscriptScan.fold(line: Data(line), into: &entry.tally, state: &entry.scan)
        }
        entry.offset += UInt64(complete.count)
        return true
    }

    /// One cache file per session rather than one shared file: concurrent sessions each run their own status line, and a single file would have them overwriting each other's counts.
    func stateURL(for transcriptPath: String) -> URL {
        let name = Self.session(of: transcriptPath)
        return cacheDirectory.appendingPathComponent(name.isEmpty ? "unnamed" : name).appendingPathExtension("json")
    }

    /// The cached state, or a fresh one when it is missing or was written by a different version.
    ///
    /// A version mismatch discards rather than migrates: the counts are per-session and cost one rescan to rebuild, which is a far cheaper failure than carrying forward numbers that meant something else.
    func loadState(for transcriptPath: String) -> State {
        guard let data = try? Data(contentsOf: stateURL(for: transcriptPath)),
              let state = try? JSONDecoder().decode(State.self, from: data),
              state.version == State.currentVersion
        else {
            return State()
        }
        return state
    }

    func save(_ state: State, for transcriptPath: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: stateURL(for: transcriptPath), options: .atomic)
    }

    /// Where the last scan of each of the session's transcripts stopped, and what it had counted by then.
    struct State: Codable {
        /// Bumped whenever what a cached count *means* changes, because a cached tally is never recomputed — only appended bytes are scanned — so carrying one across such a change would report a figure whose halves were counted under two different rules.
        ///
        /// Bumped to 2 when a denied call stopped counting: the scan gained the ids it is holding, and a cache written before that decodes with none — so a denial landing after the resume would be scored against a call the state can no longer prove it counted.
        ///
        /// Bumped to 3 when a shell command that merely *names* the binary stopped counting: a cache written before that holds calls the tool never made, and only bytes appended after it are ever scanned — so the wrong ones would sit in the total for the life of the session.
        ///
        /// Bumped to 4 when "refused" came to mean `input-refused` alone and "failed" became a count of its own: a cache written before that holds every failed call under `refusals`, so a session that crossed the deploy would go on showing three runner failures as "3 refused".
        static var currentVersion: Int {
            4
        }

        var version = currentVersion
        /// Keyed by transcript path: the session's own, plus one per subagent.
        var entries: [String: Entry] = [:]
        /// What this session's calls saved, and how far into the shared usage log that total was read.
        var usage = SessionUsage()
    }
}

private extension StatuslineReport.State {
    /// One transcript's scan position and what it had counted by then.
    struct Entry: Codable {
        var offset: UInt64 = 0
        var tally = SessionTally()
        var scan = SessionScanState()
    }
}
