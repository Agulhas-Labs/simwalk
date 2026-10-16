//
// Copyright © Agulhas Labs
//

import Foundation

/// Whose Claude Code session a command-line call belongs to, carried from the hook that saw the call to the process that makes it (SimWalk#14).
///
/// **The process cannot know this on its own, and that is the whole difficulty.** A `simwalk walk` run from an agent's shell has no session id in its environment, so its usage line went unattributed — and every line that carries a saving came from exactly that face, while the MCP face that does know its session carried none. A status line pricing its own session's calls therefore priced nothing, for a session that used the documented command line.
///
/// Claude Code's `PreToolUse` hook *does* know: its payload names the session, the tool and the command, and it fires immediately before the shell runs. So the hook leaves a slip under `callers/<session>/`, naming the arguments the binary is about to be handed, and the process claims the slip whose arguments are its own. The pattern is sift's `CallAttribution`, turned round: there the server knew its session and wanted the agent; here the process knows only its own arguments, so it looks across every session's slips for them.
///
/// **One slip per call, claimed atomically, by the call of its shape.** The shape is the whole argument vector after the binary — the verb, the target and every option — which is what both ends can see without either having to know a verb's grammar: the hook reads it off the command line as the shell will split it, and the process off its own `argv`. The claim is a rename, which succeeds for exactly one claimant, so two identical calls never take one slip.
///
/// **Shape is not identity, and where two calls share one the attribution can swap.** Two sessions running the same command at once may each be logged under the other's name; a slip whose call never ran (denied, interrupted) can be taken by a later identical call inside the claim window. A slip written from the caller's own working directory is preferred over one from anywhere else, which separates the commonest collision — parallel sessions in sibling worktrees walking the same relative walkbook — but does not close it. A command whose arguments the shell rewrites (a variable, a glob) matches nothing and is logged untagged. All of these leave the saving a floor, never a figure credited to a session that did not earn it by the rule's own lights.
///
/// Nothing here is load-bearing. Every failure is silent and leaves the log exactly as it would be without this: a line with no `session`, which every reader already handles.
public struct CallAttribution: Sendable {
    /// How long a slip can be claimed for.
    ///
    /// The claim is made as the process starts rather than when it logs, so a walk minutes long is well inside it; what it has to cover is the gap between the hook and the process — a shell starting, or a cold `swift run` build — and it is short enough that a slip whose call never ran cannot be picked up by an unrelated identical call much later.
    public static let claimWindow: TimeInterval = 120

    /// The directory holding one directory of slips per session.
    public let directory: URL

    private let now: @Sendable () -> Date

    /// The process environment ``take(arguments:workingDirectory:)`` reads `CLAUDECODE` from — a parameter so a test can supply one without touching the real environment.
    private let environment: [String: String]

    /// A seam so a test can land ``pruneSlips()``'s `rmdir` exactly in the gap the retry below exists for.
    ///
    /// Run once inside ``note(session:arguments:workingDirectory:)``, after its `createDirectory` and before its first write. A no-op outside tests.
    private let afterFirstCreate: @Sendable () -> Void

    public init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.init(directory: directory, now: now, environment: environment, afterFirstCreate: {})
    }

    init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }, environment: [String: String] = ProcessInfo.processInfo.environment, afterFirstCreate: @escaping @Sendable () -> Void) {
        self.directory = directory
        self.now = now
        self.environment = environment
        self.afterFirstCreate = afterFirstCreate
    }

    /// Beside `log`, for the reason the status line's cache is: a slip is state about the log it will tag, so a log moved by `SIMWALK_USAGE_LOG` moves the slips with it, and a test's scratch log never claims a real session's slip.
    public init(beside log: UsageLog, now: @escaping @Sendable () -> Date = { Date() }, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.init(directory: log.directory.appendingPathComponent("callers", isDirectory: true), now: now, environment: environment)
    }

    /// Records that `session` is about to run this tool with `arguments`, from `workingDirectory`.
    public func note(session: String, arguments: [String], workingDirectory: String?) {
        guard Self.isSessionName(session) else { return }
        let stamp = now().timeIntervalSince1970
        var entry: [String: Any] = ["arguments": arguments, "ts": stamp]
        if let workingDirectory {
            entry["cwd"] = Self.canonical(workingDirectory)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: entry) else { return }
        let sessionDirectory = directory.appendingPathComponent(session, isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        afterFirstCreate()
        // A name of its own per slip, so no hook run overwrites another call's slip before it is claimed.
        let name = "\(Int(stamp * 1000))-\(UUID().uuidString.prefix(8)).json"
        let slipURL = sessionDirectory.appendingPathComponent(name)
        if (try? data.write(to: slipURL, options: .atomic)) == nil {
            // Lost a race with another hook's ``pruneSlips()``, which can `rmdir` this session directory
            // between our `createDirectory` above and this write if it judges the directory empty and
            // stale at that instant. Recreate it and retry once rather than lose the slip silently.
            try? FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
            try? data.write(to: slipURL, options: .atomic)
        }
        // On every slip written: nothing else removes a slip whose call never ran or never logged, and a
        // directory that only grows is the shape of leak that gets a hook uninstalled.
        pruneSlips()
    }

    /// The session behind a call made with `arguments` from `workingDirectory`, consuming the slip that named it — `nil` when no slip of that shape is claimable.
    ///
    /// Claims only when the process runs under Claude Code (`CLAUDECODE` in ``environment``, the variable its Bash tool sets): a `PreToolUse` hook fires before the permission prompt, so a call denied there and then run by hand in the user's own terminal — or a first call whose exit leads a shell to run a second, unrelated one — would otherwise claim a slip it never earned. Outside Claude Code the slip is left for its rightful claimant.
    public func take(arguments: [String], workingDirectory: String) -> String? {
        guard environment["CLAUDECODE"] == "1" else { return nil }
        let moment = now().timeIntervalSince1970
        let here = Self.canonical(workingDirectory)
        var candidates: [Slip] = []
        for session in sessions() {
            let sessionDirectory = directory.appendingPathComponent(session, isDirectory: true)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: sessionDirectory.path)) ?? []
            for name in names where name.hasSuffix(".json") {
                let url = sessionDirectory.appendingPathComponent(name)
                guard let data = try? Data(contentsOf: url),
                      let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      entry["arguments"] as? [String] == arguments
                else {
                    continue
                }
                guard let stamp = entry["ts"] as? TimeInterval, moment - stamp <= Self.claimWindow else {
                    try? FileManager.default.removeItem(at: url)
                    continue
                }
                candidates.append(Slip(url: url, session: session, stamp: stamp, isHere: entry["cwd"] as? String == here))
            }
        }
        // This directory's first, then oldest first — the hook that ran first is the call that started first.
        let ordered = candidates.sorted { ($0.isHere ? 0 : 1, $0.stamp) < ($1.isHere ? 0 : 1, $1.stamp) }
        for slip in ordered {
            let claim = slip.url.appendingPathExtension("claimed-\(UUID().uuidString)")
            // A slip another claimant renamed first is gone, and the next is tried.
            guard rename(slip.url.path, claim.path) == 0 else { continue }
            try? FileManager.default.removeItem(at: claim)
            return slip.session
        }
        return nil
    }

    /// Forgets slips too old to be claimed, and the session directories they leave empty.
    ///
    /// Pruned at the claim window, since ``take(arguments:workingDirectory:)`` refuses anything older: this only ever removes what is already dead. A session directory goes only once it is empty *and* untouched for the window, and by `rmdir`, which refuses a directory with anything in it — so a hook run that has just created one to write into cannot have it removed from under it.
    public func pruneSlips() {
        let cutoff = now().addingTimeInterval(-Self.claimWindow)
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        for session in sessions() {
            let sessionDirectory = directory.appendingPathComponent(session, isDirectory: true)
            let entries = (try? FileManager.default.contentsOfDirectory(at: sessionDirectory, includingPropertiesForKeys: keys)) ?? []
            for entry in entries {
                let modified = try? entry.resourceValues(forKeys: Set(keys)).contentModificationDate
                guard let modified, modified < cutoff else { continue }
                try? FileManager.default.removeItem(at: entry)
            }
            let modified = try? sessionDirectory.resourceValues(forKeys: Set(keys)).contentModificationDate
            if let modified, modified < cutoff {
                rmdir(sessionDirectory.path)
            }
        }
    }
}

private extension CallAttribution {
    /// One slip found on disk: where it is, whose session it names, when its hook ran, and whether it ran from the claimant's own directory.
    struct Slip {
        let url: URL
        let session: String
        let stamp: TimeInterval
        let isHere: Bool
    }

    /// The session directories present — only names this tool could have written, so nothing else placed here is read or removed.
    func sessions() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter(Self.isSessionName)
    }

    /// Whether a session id is plainly a name, since it arrives in a hook payload and becomes a path: anything else is refused rather than sanitised, because two ids that sanitise alike would silently share their slips.
    static func isSessionName(_ session: String) -> Bool {
        !session.isEmpty && session.count <= 128
            && session.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// One spelling of a directory for both ends — `/tmp` and `/private/tmp` are the same place and must compare so.
    static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}
