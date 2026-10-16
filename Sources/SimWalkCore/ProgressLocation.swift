//
// Copyright © Agulhas Labs
//

import Foundation

/// Where a run's progress and result files live (`Docs/SIMWALK-PROGRESS.md` §1): `<directory>/progress/<session>.json` and `<session>.result.json` beside it, `directory` being the usage log's (`UsageLog.standard().directory`), so `SIMWALK_USAGE_LOG` moves both in a test.
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

    /// The result file for `session`, or for the `slot`th of its runs alive at once, written once when the run ends.
    public static func resultURL(session: String?, slot: Int = 1, in directory: URL) -> URL {
        progressDirectory(in: directory).appendingPathComponent(slotStem(session, slot) + ".result.json")
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
