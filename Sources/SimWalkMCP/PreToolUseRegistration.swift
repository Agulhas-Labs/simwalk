//
// Copyright © Agulhas Labs
//

import Foundation

/// Registers `simwalk hook pre-tool-use` as a `PreToolUse` hook in a Claude Code `settings.json`, as a pure transform over the file's bytes (SimWalk#14).
///
/// **`hooks.PreToolUse` is a list, and other tools live in it.** Unlike the single status-line slot this can merge, and it does: everything in the list stays exactly as it was except the entries that run this tool's hook, which are replaced by one — so a re-run after the binary moves repoints the hook rather than adding a second, and an uninstall takes out that entry and nothing beside it. A group holding only this tool's hook goes with it; a group somebody else shares with it keeps their hooks.
///
/// **A shape it cannot read is refused, never overwritten** — a `hooks` that is not an object, a `PreToolUse` that is not a list. Those are somebody's configuration in a form this tool did not write, and a merge that guessed would destroy it.
public struct PreToolUseRegistration {
    /// Merges the hook into `data`, or reports why it would not.
    public static func apply(to data: Data?, command: String, path: String) throws -> Outcome {
        var settings = try parse(data, path: path)
        guard var hooks = hooksObject(in: settings), var groups = preToolUse(in: hooks) else {
            return .refused(existing: unrecognised)
        }
        let ours = entries(in: groups).filter(isOurs)
        if ours.count == 1, ours.first?["command"] as? String == command, groupsHoldingOurs(groups).allSatisfy(isOurShape) {
            return .unchanged
        }
        groups = removingOurs(from: groups)
        groups.append(["matcher": matcher, "hooks": [["type": "command", "command": command, "timeout": timeout]]])
        hooks[eventName] = groups
        settings["hooks"] = hooks
        return try .installed(encoded(settings))
    }

    /// Takes this tool's hook back out, leaving every other hook where it was.
    public static func remove(from data: Data?, path: String) throws -> Removal {
        var settings = try parse(data, path: path)
        guard var hooks = hooksObject(in: settings), let groups = preToolUse(in: hooks) else {
            return .absent
        }
        let commands = entries(in: groups).filter(isOurs).compactMap { $0["command"] as? String }
        guard let command = commands.first else { return .absent }
        let remaining = removingOurs(from: groups)
        hooks[eventName] = remaining.isEmpty ? nil : remaining
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return try .removed(encoded(settings), command: command)
    }

    /// Whether a hook command is ours, at any path — matched by shape, so a moved binary's registration is recognised and replaced.
    ///
    /// **Exact, not a substring match.** `contains("simwalk") && contains(subcommand)` would also claim `/opt/bin/simwalk-guard hook pre-tool-use` — a third party's tool that merely names ours in its own filename and happens to share our subcommand. What is actually ours is the first shell word — the binary — whose last path component is exactly `simwalk`, followed by exactly `hook pre-tool-use` and nothing else.
    public static func isOurs(_ command: String?) -> Bool {
        guard let command, let (binary, rest) = firstWord(of: command) else { return false }
        guard lastPathComponent(binary) == SimWalkPaths.binaryName else { return false }
        return rest.trimmingCharacters(in: .whitespaces) == subcommand
    }

    /// The words after the binary on the registered command line.
    public static var subcommand: String {
        "hook pre-tool-use"
    }
}

private extension PreToolUseRegistration {
    /// The hook event this registers under.
    static var eventName: String {
        "PreToolUse"
    }

    /// Only shell calls can start this tool's process, and they and XcodeBuildMCP's tools are the ways to drive a simulator by hand (SimWalk#12), so only they are worth a process launch.
    static var matcher: String {
        "Bash|mcp__XcodeBuildMCP__.*"
    }

    /// Seconds Claude Code waits before giving up on the hook — generous for a hook that does one small write, and short enough that a hung one costs a call five seconds rather than the default minute.
    static var timeout: Int {
        5
    }

    static var unrecognised: String {
        "hooks of an unrecognised shape"
    }

    /// The `hooks` object — empty when there is none, `nil` when there is one this cannot read.
    static func hooksObject(in settings: [String: Any]) -> [String: Any]? {
        guard let value = settings["hooks"] else { return [:] }
        return value as? [String: Any]
    }

    /// The `PreToolUse` list — empty when there is none, `nil` when there is one this cannot read.
    static func preToolUse(in hooks: [String: Any]) -> [Any]? {
        guard let value = hooks[eventName] else { return [] }
        return value as? [Any]
    }

    /// Every hook entry in every group, skipping any part of the list in a shape this does not read.
    static func entries(in groups: [Any]) -> [[String: Any]] {
        groups.flatMap { group -> [[String: Any]] in
            guard let group = group as? [String: Any], let hooks = group["hooks"] as? [Any] else { return [] }
            return hooks.compactMap { $0 as? [String: Any] }
        }
    }

    static func isOurs(_ entry: [String: Any]) -> Bool {
        isOurs(entry["command"] as? String)
    }

    /// The command's first shell word — quoted (`"/path/simwalk"`) or bare — and everything after it, trimmed of the separating space.
    ///
    /// `nil` for an unterminated quote, which is not a shape this ever writes.
    static func firstWord(of command: String) -> (word: String, rest: Substring)? {
        var body = Substring(command).drop { $0 == " " }
        if body.first == "\"" {
            body = body.dropFirst()
            guard let close = body.firstIndex(of: "\"") else { return nil }
            return (String(body[..<close]), body[body.index(after: close)...])
        }
        guard let space = body.firstIndex(of: " ") else { return (String(body), Substring()) }
        return (String(body[..<space]), body[space...])
    }

    /// The last path component of a shell word, without pulling in a `URL` or `NSString` for what is a plain string split.
    static func lastPathComponent(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// The groups carrying one of this tool's entries.
    static func groupsHoldingOurs(_ groups: [Any]) -> [[String: Any]] {
        groups.compactMap { $0 as? [String: Any] }.filter { !entries(in: [$0]).filter(isOurs).isEmpty }
    }

    /// Whether a group is exactly the one this would write — so a re-run leaves it alone.
    static func isOurShape(_ group: [String: Any]) -> Bool {
        guard group["matcher"] as? String == matcher, let hooks = group["hooks"] as? [Any], hooks.count == 1,
              let entry = hooks.first as? [String: Any]
        else {
            return false
        }
        return entry["timeout"] as? Int == timeout && entry["type"] as? String == "command"
    }

    /// The list with this tool's entries taken out, and any group they leave empty with them — every other entry and group untouched.
    static func removingOurs(from groups: [Any]) -> [Any] {
        groups.compactMap { element -> Any? in
            guard var group = element as? [String: Any], let hooks = group["hooks"] as? [Any] else { return element }
            let kept = hooks.filter { !(($0 as? [String: Any]).map(isOurs) ?? false) }
            guard kept.count != hooks.count else { return element }
            guard !kept.isEmpty else { return nil }
            group["hooks"] = kept
            return group
        }
    }

    static func parse(_ data: Data?, path: String) throws -> [String: Any] {
        guard let data, !data.isEmpty else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StatuslineRegistrationError.settingsNotAnObject(path: path)
        }
        return object
    }

    static func encoded(_ settings: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}

public extension PreToolUseRegistration {
    /// What the merge did, so the installer can report it rather than claim success blandly.
    enum Outcome: Equatable, Sendable {
        case installed(Data)
        /// Already registered at exactly this command — the re-run case.
        case unchanged
        /// The hooks are in a shape this cannot merge into without guessing.
        case refused(existing: String)
    }

    /// What the removal did, so the uninstaller can report it rather than claim success blandly.
    enum Removal: Equatable, Sendable {
        case removed(Data, command: String)
        /// No hook of this tool's was registered — nothing to undo.
        case absent
    }
}
