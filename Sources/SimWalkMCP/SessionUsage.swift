//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// What one session's calls saved, how many failed and how many were refused, read from the shared usage log.
///
/// The transcript scan counts calls and cannot price them: a transcript records that an answer was served, never what looking at the material instead would have cost. That is measured at call time and written to the usage log — but the log is shared by every session on the machine, so a time window over it would hand one session another's saving whenever two ran at once, which is the one direction a saving must never round. The MCP face records `CLAUDE_CODE_SESSION_ID` on the line it writes, so the sum is exact rather than apportioned.
///
/// **A shell call is absent from this by construction, and the segment must not claim for it.** The CLI records no session, so it contributes no saving here, no failure and no refusal — it is counted, and nothing more is said about it.
///
/// Read incrementally, as the transcript scan is and for the same reason: this runs on every status-line render, and the log is the largest file the tool keeps.
public struct SessionUsage: Codable, Equatable, Sendable {
    /// The tokens the session's measured calls saved.
    public var tokensSaved = 0

    /// How many of the session's calls failed — ``UsageLog/Entry/isFailure``, the tool not answering for any reason but a caller's own argument, which is what `simwalk usage` counts as a failure.
    public var failures = 0

    /// How many of the session's calls were refused — ``UsageLog/Entry/isRefusal``, a caller's own argument turned away (`input-refused`), which `simwalk usage` leaves out of its failures.
    public var refusals = 0

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
            scanned.tokensSaved += entry.tokensSaved ?? 0
            // "Failed" and "refused" mean the same here as in `simwalk usage`, because both read the one
            // pair of predicates on `Entry`. Counting every failed call as a refusal folded the two into one
            // word; counting only refusals left a session whose every walk fell over reading as clean.
            scanned.failures += entry.isFailure ? 1 : 0
            scanned.refusals += entry.isRefusal ? 1 : 0
        }
        scanned.offset = carried.offset + UInt64(complete.count)
        return scanned
    }
}
