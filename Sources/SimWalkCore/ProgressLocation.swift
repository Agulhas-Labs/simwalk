//
// Copyright © Agulhas Labs
//

import Foundation

/// Where a run's progress and result files live (`Docs/SIMWALK-PROGRESS.md` §1): `<directory>/progress/<session>.json` and, beside it, a result file per walk named by its handle (`<stem>@<pid>-<startedAtMs>.result.json`), `directory` being the usage log's (`UsageLog.standard().directory`), so `SIMWALK_USAGE_LOG` moves both in a test.
///
/// **Per session, never per project**: parallel sessions in sibling worktrees share a project and must not share a file. A session is used as a filename only when it is made of `[A-Za-z0-9_-]` alone — a Claude Code session id is a UUID — and anything else, absent, blank or able to name a path (`../x`, `a/b`), is ``defaultSession``: a run that cannot be told apart is written where a human's CLI run is, never somewhere its id points.
///
/// **Per live run, too**: two runs alive at once never share a file, whatever their sessions (SimWalk#83). The first takes the session's own `<session>.json`; one starting while it runs takes `<session>.2.json`, and on — ``ProgressClaim`` decides which.
public struct ProgressLocation {
    /// The session name a run with no usable session id is filed under.
    public static var defaultSession: String {
        "default"
    }

    /// The progress file for `session`, or for the `slot`th of its runs alive at once (``ProgressClaim``): `<session>.json`, then `<session>.2.json` and on.
    public static func progressURL(session: String?, slot: Int = 1, in directory: URL) -> URL {
        progressDirectory(in: directory).appendingPathComponent(slotStem(session, slot) + ".json")
    }

    /// The result file of the walk `pid` started at `startedAt` in `session`'s `slot`th run: `<stem>@<pid>-<startedAtMs>.result.json`, the walk's ``WalkHandle`` text, written once when the run ends.
    ///
    /// Named by the walk, not by the slot: a later run reuses the slot's progress file, and must not overwrite the result of one a caller has still to read.
    public static func resultURL(session: String?, slot: Int = 1, pid: Int32, startedAt: Date, in directory: URL) -> URL {
        let handle = WalkHandle(stem: slotStem(session, slot), pid: pid, startedAtMs: WalkHandle.milliseconds(startedAt))
        return resultURL(of: handle, in: directory)
    }

    /// The result file of the walk `handle` names.
    public static func resultURL(of handle: WalkHandle, in directory: URL) -> URL {
        progressDirectory(in: directory).appendingPathComponent(handle.text + resultSuffix)
    }

    /// The ending of a result file's name.
    static var resultSuffix: String {
        ".result.json"
    }

    /// Removes the result files beside `resultURL` (the one a walk just wrote) last modified more than `age` seconds before `now`, and nothing else.
    ///
    /// A walk that writes its result calls this, so the directory holds a week of results rather than every walk ever made (`Docs/SIMWALK-PROGRESS.md` §1). Best effort: a file that cannot be listed or removed is left.
    public static func pruneResults(beside resultURL: URL, olderThan age: TimeInterval = 7 * 24 * 3600, now: Date = Date()) {
        let folder = resultURL.deletingLastPathComponent()
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.lastPathComponent.hasSuffix(resultSuffix) {
            guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now.timeIntervalSince(modified) > age
            else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// The lock file a run holds for as long as it owns `slot`'s two files (``ProgressClaim``).
    static func claimURL(session: String?, slot: Int, in directory: URL) -> URL {
        progressDirectory(in: directory).appendingPathComponent(slotStem(session, slot) + ".lock")
    }

    /// `session` when it is safe as a filename, else ``defaultSession``.
    public static func fileStem(_ session: String?) -> String {
        guard let session, !session.isEmpty, session.unicodeScalars.allSatisfy(isAllowed) else {
            return defaultSession
        }
        return session
    }

    /// The stem of `slot`'s files: the session's own for the first, `<stem>.<slot>` after it — a dot no stem can hold, so no slot names another session's file.
    private static func slotStem(_ session: String?, _ slot: Int) -> String {
        slot > 1 ? "\(fileStem(session)).\(slot)" : fileStem(session)
    }

    static func progressDirectory(in directory: URL) -> URL {
        directory.appendingPathComponent("progress", isDirectory: true)
    }

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-")
    }
}
