//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkMCP
import Testing

/// Claude Code's `statusLine` is a single slot holding somebody's own configuration, so the only two things worth pinning are that this takes it when it is free and refuses it when it is not.
struct StatuslineRegistrationTests {
    @Test
    func afreeSlotIsTakenAndNamesThisBinary() throws {
        let outcome = try StatuslineRegistration.apply(to: nil, command: Self.ours, path: "settings.json")

        guard case let .installed(data) = outcome else {
            Issue.record("expected an install into a free slot, got \(outcome)")
            return
        }
        let settings = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let slot = try #require(settings["statusLine"] as? [String: Any])

        #expect(slot["command"] as? String == Self.ours)
        #expect(slot["type"] as? String == "command")
    }

    @Test
    func theRestOfTheSettingsFileSurvivesTheMerge() throws {
        let existing = try JSONSerialization.data(withJSONObject: ["model": "opus", "hooks": ["SessionStart": []]])

        let outcome = try StatuslineRegistration.apply(to: existing, command: Self.ours, path: "settings.json")

        guard case let .installed(data) = outcome else {
            Issue.record("expected an install beside the existing keys, got \(outcome)")
            return
        }
        let settings = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(settings["model"] as? String == "opus")
        #expect(settings["hooks"] is [String: Any])
    }

    /// A status line somebody built is never clobbered — composing two is their call, and guessing at how would mangle output they wrote.
    @Test
    func asomebodyElsesStatusLineIsRefusedAndNamed() throws {
        let existing = try Self.settings(command: "~/bin/my-prompt.sh")

        let outcome = try StatuslineRegistration.apply(to: existing, command: Self.ours, path: "settings.json")

        #expect(outcome == .refused(existing: "~/bin/my-prompt.sh"))
    }

    /// A slot holding something this cannot read is still a slot somebody filled, so an unrecognised shape is refused rather than falling past the check.
    @Test
    func aslotOfAnUnrecognisedShapeIsRefusedRatherThanOverwritten() throws {
        let existing = try JSONSerialization.data(withJSONObject: ["statusLine": "just a string"])

        let outcome = try StatuslineRegistration.apply(to: existing, command: Self.ours, path: "settings.json")

        #expect(outcome == .refused(existing: "a status line of an unrecognised shape"))
    }

    @Test
    func areRunAtTheSameCommandChangesNothing() throws {
        let existing = try Self.settings(command: Self.ours)

        #expect(try StatuslineRegistration.apply(to: existing, command: Self.ours, path: "settings.json") == .unchanged)
    }

    /// A moved binary is repointed rather than left beside a stale registration, which is what makes re-running the installer the upgrade path.
    @Test
    func amovedBinaryIsRepointed() throws {
        let existing = try Self.settings(command: "/opt/simwalk statusline")

        let outcome = try StatuslineRegistration.apply(to: existing, command: Self.ours, path: "settings.json")

        guard case let .installed(data) = outcome else {
            Issue.record("expected a repointed registration, got \(outcome)")
            return
        }
        let settings = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect((settings["statusLine"] as? [String: Any])?["command"] as? String == Self.ours)
    }

    @Test
    func removalTakesOnlyOurOwnRegistration() throws {
        let ours = try Self.settings(command: Self.ours)
        let theirs = try Self.settings(command: "~/bin/my-prompt.sh")

        let removed = try StatuslineRegistration.remove(from: ours, path: "settings.json")

        guard case let .removed(data, command) = removed else {
            Issue.record("expected our own registration to be removed, got \(removed)")
            return
        }
        let settings = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(command == Self.ours)
        #expect(settings["statusLine"] == nil)
        #expect(try StatuslineRegistration.remove(from: theirs, path: "settings.json") == .notOurs(existing: "~/bin/my-prompt.sh"))
        #expect(try StatuslineRegistration.remove(from: nil, path: "settings.json") == .absent)
    }

    /// The file is somebody's whole Claude Code configuration, so one this cannot parse is refused rather than replaced with something it can.
    @Test
    func asettingsFileThisCannotParseIsRefusedRatherThanReplaced() {
        let notAnObject = Data("[1, 2, 3]".utf8)

        #expect(throws: StatuslineRegistrationError.settingsNotAnObject(path: "settings.json")) {
            try StatuslineRegistration.apply(to: notAnObject, command: Self.ours, path: "settings.json")
        }
    }

    private static var ours: String {
        "/Users/x/.local/bin/simwalk statusline"
    }

    private static func settings(command: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["statusLine": ["type": "command", "command": command]])
    }
}
