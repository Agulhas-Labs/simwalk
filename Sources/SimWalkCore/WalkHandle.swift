//
// Copyright © Agulhas Labs
//

import Foundation

/// The name a bounded MCP walk is polled by (`Docs/Reference.md`, "Bounded walks"): `<stem>@<pid>-<startedAtMs>`.
///
/// The stem alone is re-claimed by the next walk on the machine, so a handle carries the two schema v1 keys that tell walks apart: the walk's `pid` and the progress file's `startedAt` in epoch milliseconds. A handle is used as a file name, so ``init(parsing:)`` accepts only `^[A-Za-z0-9_-]+(\.[0-9]+)?@[0-9]+-[0-9]+$` and a reader checks that before it touches the filesystem.
public struct WalkHandle: Equatable, Sendable {
    /// The progress-file stem: `<session>` or `<session>.<slot>`.
    public let stem: String
    public let pid: Int32
    /// The file's `startedAt`, epoch milliseconds.
    public let startedAtMs: Int64

    public init(stem: String, pid: Int32, startedAtMs: Int64) {
        self.stem = stem
        self.pid = pid
        self.startedAtMs = startedAtMs
    }

    /// The handle `text` spells, or `nil` when it does not match the grammar (or its numbers do not fit).
    public init?(parsing text: String) {
        guard let match = text.wholeMatch(of: #/([A-Za-z0-9_-]+(?:\.[0-9]+)?)@([0-9]+)-([0-9]+)/#),
              let pid = Int32(match.2),
              let startedAtMs = Int64(match.3)
        else {
            return nil
        }
        self.init(stem: String(match.1), pid: pid, startedAtMs: startedAtMs)
    }

    /// The handle for the walk whose progress file is `stem` and holds `progress`.
    public init(stem: String, progress: WalkProgress) {
        self.init(stem: stem, pid: progress.pid, startedAtMs: Self.milliseconds(progress.startedAt))
    }

    /// The handle as it is printed and polled with.
    public var text: String {
        "\(stem)@\(pid)-\(startedAtMs)"
    }

    /// Whether `progress` is the run this handle names: the same `pid` and the same `startedAt` to the millisecond.
    func names(_ progress: WalkProgress) -> Bool {
        progress.pid == pid && Self.milliseconds(progress.startedAt) == startedAtMs
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}
