//
// Copyright © Agulhas Labs
//

import Foundation

/// Appends one JSON line per call to `~/.simwalk/usage.jsonl` (Brief §3), so adoption and failure triage are ground truth rather than anecdote.
///
/// **A logging failure is never allowed to reach the caller.** Every write is best-effort: a read-only home directory, a full disk, or a permission change makes calls go unrecorded and changes nothing else — not the command's output, not its exit code, and above all not the MCP face's stdout, which carries JSON-RPC only. That is why `record` neither throws nor returns a result: there is no failure here worth a caller's attention, and offering one would invite a call site to act on it.
public struct UsageLog: Sendable {
    /// The log file itself.
    public let fileURL: URL
    /// The clock, injected rather than read — the core takes its time inputs explicitly so a walk is reproducible and a test can assert the line it wrote.
    private let now: @Sendable () -> Date

    public init(fileURL: URL, now: @escaping @Sendable () -> Date) {
        self.fileURL = fileURL
        self.now = now
    }

    /// The log at `usage.jsonl` inside `directory`.
    public init(directory: URL, now: @escaping @Sendable () -> Date) {
        self.init(fileURL: directory.appendingPathComponent(Self.standardFileName), now: now)
    }

    /// The directory the log lives in — and where the state kept beside it (the status line's scan cache, the report's redaction salt) goes, so a log moved by ``overrideVariable`` takes that state with it.
    public var directory: URL {
        fileURL.deletingLastPathComponent()
    }

    /// The variable that moves the log: a path to the file itself, honoured by ``standard(environment:)``.
    ///
    /// **Anything that drives the binary and is not a real use of it sets this** — a test, a review, a mutation run — so what it records lands in a file it owns rather than in the one `simwalk usage` reports adoption and failures from. `HOME` cannot do that job: `homeDirectoryForCurrentUser` ignores it.
    public static var overrideVariable: String {
        "SIMWALK_USAGE_LOG"
    }

    // Host-only: `homeDirectoryForCurrentUser` is unavailable on iOS, and rightly — the runner executes
    // inside a simulator where `~` is an app container, so a "standard location" there would be a
    // per-install directory nobody could find and nothing could aggregate. The log's own machinery is
    // platform-neutral; it is only *this* location that is a fact about the host.
    #if os(macOS)
    /// The log every face writes to in normal use: `~/.simwalk/usage.jsonl`, or the file ``overrideVariable`` names, on the system clock.
    ///
    /// Takes no `FileManager`. It used to, and honoured it only for locating home — the append itself is a raw `open(2)`, which is the point of the type and has no `FileManager` spelling — so the parameter read as injection at a call site while half the type ignored it. A test that wants a different filesystem view passes `init(fileURL:now:)` a file, which is the whole of what the log needs told.
    ///
    /// A blank override is no override: an unset-by-emptying variable (`SIMWALK_USAGE_LOG= simwalk …`) would otherwise name the working directory as a file.
    public static func standard(environment: [String: String] = ProcessInfo.processInfo.environment) -> UsageLog {
        if let override = environment[overrideVariable], !override.trimmed.isEmpty {
            return UsageLog(fileURL: URL(fileURLWithPath: override), now: { Date() })
        }
        return UsageLog(directory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".simwalk"), now: { Date() })
    }
    #endif

    /// The log's own name inside the directory it lives in.
    private static var standardFileName: String {
        "usage.jsonl"
    }

    /// Records one call.
    ///
    /// `tool` is the CLI subcommand or MCP tool name; `target` is what it was pointed at; `err` carries one bounded line when the call failed, so triage does not require re-running it.
    ///
    /// `saving` is what the answer stood in for, where it stood in for anything. It is omitted rather than zeroed for a call that weighed nothing — a validation stands in for no screenshot and no tree, and a line claiming it saved nothing would put that call in the denominator of every ratio drawn over this file.
    ///
    /// `session` is whose Claude Code session the call belongs to, so a status line can price its own calls and nobody else's. It is a parameter rather than an environment read inside this type, on the same rule the clock follows: which face attributes a call to a session is a decision at the call site. The MCP face passes its own; the CLI passes the session a `PreToolUse` hook slip names for its arguments (``CallAttribution``, SimWalk#14), and nothing when there is none — a CLI is also run by hand and by scripts under no session at all, and a session guessed at would credit one session with another's saving.
    ///
    /// `kind` says why a failed call failed — `nil` for a call that succeeded, where a kind means nothing, and for a failure whose site has not been mapped to one (``UsageFailureKind``). Read off the thrown error at the call site (``UsageFailureKind/of(_:)``) or stated directly, never inferred here: this type only ever writes what it is told.
    public func record(tool: String, target: String?, milliseconds: Int, succeeded: Bool, err: String? = nil, saving: ContextSaving? = nil, session: String? = nil, kind: UsageFailureKind? = nil) {
        let entry = Entry(
            timestamp: Timestamp.string(from: now()),
            tool: tool,
            target: target,
            milliseconds: milliseconds,
            succeeded: succeeded,
            error: err.map { String($0.prefix(Self.errorLimit)).replacingOccurrences(of: "\n", with: " ") },
            session: session,
            screenshots: saving.map(\.screenshotTokens.count),
            imageTokens: saving.map { $0.screenshotTokens.reduce(0, +) },
            treeBytes: saving?.treeBytes,
            answerBytes: saving?.servedBytes,
            kind: kind
        )
        let encoder = JSONEncoder()
        // Paths are most of what a log line carries, and an escaped one is unreadable when triaging.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let line = try? encoder.encode(entry) else { return }
        append(line + Data("\n".utf8))
    }

    /// One bounded line: enough to group failures by reason, never enough to turn the log into the payload it is recording.
    private static var errorLimit: Int {
        200
    }

    /// Appends one line with `O_APPEND` and a single `write(2)`.
    ///
    /// Both halves are load-bearing under concurrency, and several SimWalk processes writing at once is the normal case — a fleet of walkers is the point of Brief §2.4. `O_APPEND` makes the seek-to-end and the write one atomic step in the kernel, where `FileHandle.seekToEnd` then `write` is two, and a second writer landing between them overwrites the first's line. One `write` per line then keeps a line whole: a short record written in a single call is not interleaved with another process's. Creating with `O_CREAT` rather than an atomic first-write also removes the window where two processes each decided the file did not exist and one replaced the other's first line.
    private func append(_ line: Data) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = fileURL.path.withCString { path in
            open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        }
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        line.withUnsafeBytes { buffer in
            guard var pointer = buffer.baseAddress else { return }
            var remaining = buffer.count
            // A short write, or an interrupted one, would otherwise truncate the line and leave the
            // file unparseable from that byte on — the discarded return value was the whole claim.
            while remaining > 0 {
                let written = write(descriptor, pointer, remaining)
                guard written > 0 else {
                    if written < 0, errno == EINTR {
                        continue
                    }
                    return
                }
                pointer += written
                remaining -= written
            }
        }
    }
}

public extension UsageLog {
    /// One recorded call — the line format `~/.simwalk/usage.jsonl` carries, kept as a type so a reader of the log and its writer cannot disagree about the keys.
    ///
    /// The wire keys are terse (`ts`, `ms`, `ok`, `err`) because a log line is read a million at a time by `jq`, and matching Sift's shape means one habit covers both tools. The Swift properties are spelled out and `CodingKeys` bridges the two, rather than naming a property after the byte budget.
    struct Entry: Codable, Equatable, Sendable {
        /// When the call was made, ISO-8601 in UTC.
        public var timestamp: String
        /// The CLI subcommand or MCP tool name.
        public var tool: String
        /// What the call was pointed at, when it was pointed at anything.
        public var target: String?
        /// How long the call took, in milliseconds.
        public var milliseconds: Int
        /// Whether the call answered rather than refused.
        public var succeeded: Bool
        /// One bounded line naming why a failed call failed.
        public var error: String?

        /// Whose Claude Code session made the call; absent for every call made outside one, and on every line written before the field existed.
        public var session: String?

        /// How many screenshots this answer stood in for; absent where it stood in for none, and on every line written before the fields existed.
        public var screenshots: Int?
        /// What those screenshots would have cost to look at, at ``ImageTokenEstimate``'s constants.
        public var imageTokens: Int?
        /// The bytes of accessibility tree this answer stood in for.
        public var treeBytes: Int?
        /// The bytes the answer itself cost.
        public var answerBytes: Int?

        /// Why the call failed, for a failed call whose site is mapped to one; absent for a call that succeeded, and on every line written before this field existed (``UsageFailureKind/inferred(fromErrorText:)`` reads those from ``error`` instead).
        ///
        /// `nil` also for a line whose `kind` field this build does not recognise — decoding never fails over a value it cannot place, since several binaries at different commits write to this file and a kind a newer one added must not take the whole line down for an older reader. The raw text of an unrecognised value survives in ``unrecognizedKind`` rather than being discarded, so a reader can tell that case apart from a line that never carried a kind at all.
        public var kind: UsageFailureKind?

        /// The literal `kind` text a line carried when it did not decode as any case this build knows — `nil` on every line that decoded cleanly, whether because it carries a known kind or none at all.
        ///
        /// Never written by this build (there is no `UsageFailureKind` case it would refuse to encode), and excluded from `CodingKeys` accordingly: it exists only to carry forward what a newer binary's line said, for `simwalk usage` to report as a gap rather than silently fold into the same bucket as a line that said nothing.
        public var unrecognizedKind: String?

        public init(
            timestamp: String,
            tool: String,
            target: String?,
            milliseconds: Int,
            succeeded: Bool,
            error: String?,
            session: String? = nil,
            screenshots: Int? = nil,
            imageTokens: Int? = nil,
            treeBytes: Int? = nil,
            answerBytes: Int? = nil,
            kind: UsageFailureKind? = nil
        ) {
            self.timestamp = timestamp
            self.tool = tool
            self.target = target
            self.milliseconds = milliseconds
            self.succeeded = succeeded
            self.error = error
            self.session = session
            self.screenshots = screenshots
            self.imageTokens = imageTokens
            self.treeBytes = treeBytes
            self.answerBytes = answerBytes
            self.kind = kind
        }

        /// Decodes leniently over `kind`: a value this build's `UsageFailureKind` has no case for must not fail the whole line.
        ///
        /// Several binaries at different commits append to this file and a kind a newer one wrote has to remain readable — as everything else on the line, including whether the call failed at all — by an older reader. Every other field decodes exactly as `Codable` would synthesize it.
        ///
        /// **A `kind` that is present but not a string decodes the same way** — `unrecognizedKind` holding its text — rather than failing the whole line. `decodeIfPresent(String.self, forKey:)` only returns `nil` for an absent or `null` value; a value of the wrong JSON *type* throws, and a bare `try?` around it would have collapsed that case into "no kind stored at all", the exact ambiguity `unrecognizedKind` exists to keep apart from.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            timestamp = try container.decode(String.self, forKey: .timestamp)
            tool = try container.decode(String.self, forKey: .tool)
            target = try container.decodeIfPresent(String.self, forKey: .target)
            milliseconds = try container.decode(Int.self, forKey: .milliseconds)
            succeeded = try container.decode(Bool.self, forKey: .succeeded)
            error = try container.decodeIfPresent(String.self, forKey: .error)
            session = try container.decodeIfPresent(String.self, forKey: .session)
            screenshots = try container.decodeIfPresent(Int.self, forKey: .screenshots)
            imageTokens = try container.decodeIfPresent(Int.self, forKey: .imageTokens)
            treeBytes = try container.decodeIfPresent(Int.self, forKey: .treeBytes)
            answerBytes = try container.decodeIfPresent(Int.self, forKey: .answerBytes)
            if container.contains(.kind), try !container.decodeNil(forKey: .kind) {
                let stringKind = try? container.decode(String.self, forKey: .kind)
                let rawKind = stringKind ?? Self.nonStringKindText(in: container)
                kind = stringKind.flatMap(UsageFailureKind.init(rawValue:))
                unrecognizedKind = kind == nil ? rawKind : nil
            } else {
                kind = nil
                unrecognizedKind = nil
            }
        }

        /// The text a `kind` that failed to decode as a `String` reports as — a JSON scalar this line's writer used instead, read as whichever type it actually is.
        ///
        /// Never reached by a value this build itself would write; it exists only so a line another kind of writer produced still decodes as an unrecognised kind rather than an unreadable line.
        private static func nonStringKindText(in container: KeyedDecodingContainer<CodingKeys>) -> String {
            if let value = try? container.decode(Bool.self, forKey: .kind) {
                return String(value)
            }
            if let value = try? container.decode(Int.self, forKey: .kind) {
                return String(value)
            }
            if let value = try? container.decode(Double.self, forKey: .kind) {
                return String(value)
            }
            return "<unreadable kind>"
        }

        /// What this call saved, or `nil` where it weighed nothing.
        ///
        /// All three halves or none: a line carrying an answer's size but no denominator measured nothing, and pricing it as a saving of everything it served would be the arithmetic running backwards. Priced through ``ContextSaving/saved(imageTokens:treeBytes:servedBytes:)`` so a month of lines and the answers that wrote them cannot disagree.
        public var tokensSaved: Int? {
            guard let imageTokens, let treeBytes, let answerBytes else { return nil }
            return ContextSaving.saved(imageTokens: imageTokens, treeBytes: treeBytes, servedBytes: answerBytes)
        }
    }
}

extension UsageLog.Entry {
    /// The terse wire keys, bridged here so no property has to be named after the byte budget.
    ///
    /// The measured four and the session are optional on both sides, so a line written before they existed decodes with them absent rather than failing — which matters because the log on a machine that has been running this tool since August is mostly such lines, and a reader that refused them would report the tool as unused.
    enum CodingKeys: String, CodingKey {
        case timestamp = "ts"
        case tool
        case target
        case milliseconds = "ms"
        case succeeded = "ok"
        case error = "err"
        case session
        case screenshots = "shots"
        case imageTokens = "imgTokens"
        case treeBytes
        case answerBytes = "outBytes"
        case kind
    }
}
