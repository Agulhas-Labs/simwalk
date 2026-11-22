//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// What one session's calls saved, how many failed and how many were refused, read from the shared usage log.
///
/// The transcript scan counts calls and cannot price them: a transcript records that an answer was served, never what looking at the material instead would have cost. That is measured at call time and written to the usage log — but the log is shared by every session on the machine, so a time window over it would hand one session another's saving whenever two ran at once, which is the one direction a saving must never round. The MCP face records `CLAUDE_CODE_SESSION_ID` on the line it writes, so the sum is exact rather than apportioned.
///
/// Both faces write the session: the MCP face and the command line each record `CLAUDE_CODE_SESSION_ID` on the line they write, so a shell call is counted, priced and judged here like any other. A session with no tagged line at all — an older Claude Code whose shell calls go untagged — is the one the status line counts from the transcript instead.
///
/// Read incrementally, as the transcript scan is and for the same reason: this runs on every status-line render, and the log is the largest file the tool keeps.
public struct SessionUsage: Codable, Equatable, Sendable {
    /// The figures over the session's tagged lines — calls, walks, failures, refusals and the saving — from the one function `simwalk usage --session` reads, with the screenshots already priced carried so a later call over the same pixels is not counted again, in this render or a later one.
    public private(set) var summary = UsageSummary()

    /// The tokens the session's calls saved: the screenshots priced, less every byte served.
    public var tokensSaved: Int {
        summary.tokensSaved
    }

    /// How many of the session's calls failed.
    public var failures: Int {
        summary.failures
    }

    /// How many of the session's calls were refused.
    public var refusals: Int {
        summary.refusals
    }

    /// Where the last read of the shared log stopped.
    public var offset: UInt64 = 0

    /// Adds what `session` did in whatever has been appended to `fileURL` since the last read.
    public static func scanning(_ fileURL: URL, after previous: SessionUsage, session: String) -> SessionUsage {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return previous }
        defer { try? handle.close() }

        // A shrunken log is a different log under the same name — deleted, or rotated — so the offset into
        // it means nothing, and every total counted through it means nothing either.
        var carried = previous
        let size = (try? handle.seekToEnd()) ?? 0
        if size < previous.offset {
            carried = SessionUsage()
        }
        guard size > carried.offset else { return carried }

        try? handle.seek(toOffset: carried.offset)
        guard let appended = try? handle.readToEnd(), !appended.isEmpty else { return carried }
        // The writer may be mid-line: half a JSON object decodes as nothing, and moving the offset past it
        // would lose the whole call rather than re-read it next time.
        guard let lastNewline = appended.lastIndex(of: 0x0A) else { return carried }
        let complete = appended[appended.startIndex ... lastNewline]

        var scanned = carried
        let decoder = JSONDecoder()
        for line in complete.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let entry = try? decoder.decode(UsageLog.Entry.self, from: Data(line)),
                  entry.session == session
            else {
                continue
            }
            // "Failed" and "refused" mean the same here as in `simwalk usage` because both come out of one
            // ``UsageSummary``.
            scanned.summary.add(entry)
        }
        scanned.offset = carried.offset + UInt64(complete.count)
        return scanned
    }
}
