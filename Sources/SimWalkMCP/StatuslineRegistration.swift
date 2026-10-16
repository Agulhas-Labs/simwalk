//
// Copyright © Agulhas Labs
//

import Foundation

/// Registers the status-line command in a Claude Code `settings.json`, as a pure transform over the file's bytes.
///
/// **`statusLine` is a single slot, not a list.** Claude Code runs one command and displays what it prints, so this cannot merge the way a hook list does, and installing unconditionally would silently destroy whatever status line the user had already built. It refuses instead and says what it found: a status line is someone's own configuration, and a tool that eats it to advertise itself has misjudged its own importance.
///
/// This is the fallback path. Where sift is on the machine it owns the slot and runs every executable in its segment directory, so simwalk lands there instead — see ``StatuslineSegments``, which is what `install-hook` prefers.
public struct StatuslineRegistration {
    /// Merges the status-line command into `data`, or reports why it would not.
    public static func apply(to data: Data?, command: String, path: String) throws -> Outcome {
        var settings = try parse(data, path: path)

        if let value = settings["statusLine"] {
            // A slot holding something this cannot read is still a slot somebody filled, so an
            // unrecognised shape is refused rather than falling past the check and being overwritten.
            guard let existing = value as? [String: Any] else {
                return .refused(existing: unrecognised)
            }
            let previous = existing["command"] as? String
            guard isOurs(previous) else {
                return .refused(existing: previous ?? unrecognised)
            }
            guard previous != command else {
                return .unchanged
            }
        }

        settings["statusLine"] = ["type": "command", "command": command]
        return try .installed(encoded(settings))
    }

    /// Empties the status-line slot, but only when this tool is what is in it.
    ///
    /// The single slot cuts the same way on the way out as on the way in: an uninstall that cleared it unconditionally would delete a status line somebody built, which is worse than leaving one of ours behind.
    public static func remove(from data: Data?, path: String) throws -> Removal {
        var settings = try parse(data, path: path)
        guard let value = settings["statusLine"] else { return .absent }
        guard let existing = value as? [String: Any] else {
            return .notOurs(existing: unrecognised)
        }
        let command = existing["command"] as? String
        guard let command, isOurs(command) else {
            return .notOurs(existing: command ?? unrecognised)
        }

        settings.removeValue(forKey: "statusLine")
        return try .removed(encoded(settings), command: command)
    }

    /// Whether a configured status-line command is ours, at any path.
    ///
    /// Matched by shape rather than by exact path, so a re-run after the binary moves replaces the old registration instead of sitting beside a stale one.
    public static func isOurs(_ command: String?) -> Bool {
        guard let command else { return false }
        return SimWalkPaths.namesThisTool(command) && command.contains("statusline")
    }
}

private extension StatuslineRegistration {
    /// What a slot holding something unreadable is called in a report, so the two paths that find one say the same thing.
    static var unrecognised: String {
        "a status line of an unrecognised shape"
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

public extension StatuslineRegistration {
    /// What the merge did, so the installer can report it rather than claim success blandly.
    enum Outcome: Equatable, Sendable {
        case installed(Data)
        /// Already registered at exactly this command — the re-run case.
        case unchanged
        /// A status line somebody configured themselves is in the slot, and this will not take it.
        case refused(existing: String)
    }

    /// What the removal did, so the uninstaller can report it rather than claim success blandly.
    enum Removal: Equatable, Sendable {
        case removed(Data, command: String)
        /// No status line was configured at all — nothing to undo.
        case absent
        /// Something this tool did not register is in the slot, and an uninstall will not take it either.
        case notOurs(existing: String)
    }
}
