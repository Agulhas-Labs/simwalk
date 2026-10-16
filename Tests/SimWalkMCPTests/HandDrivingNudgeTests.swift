//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkMCP
import SimWalkTestSupport
import Testing

/// Driving a simulator by hand where a walkbook already drives it is refused once, priced, and let through when the same simulator command is run again, alone or in any company (SimWalk#80) — and nothing else is ever refused (SimWalk#12).
struct HandDrivingNudgeTests {
    /// **The regression this exists for.** A screenshot by hand in a repository with a walkbook is refused, naming the walkbook and the command that walks it.
    @Test
    func ascreenshotByHandBesideAWalkbookIsRefusedNamingIt() throws {
        let repo = try Repo(walkbook: true)

        let output = try #require(repo.hook("xcrun simctl io booted screenshot a.png"))
        let reason = try Self.reason(in: output)

        #expect(output.contains(#""permissionDecision":"deny""#))
        #expect(reason.contains("simwalk walk Docs/Walkbooks/x.json"))
        #expect(reason.contains("2 screens / 3 states in one command, vs one turn per tap"))
    }

    /// The refusal keeps the re-run for a one-off capture and sends AX probing to `simwalk inspect`, as the guide does — never to the re-run of a screenshot, as SimWalk#49 left the guide.
    @Test
    func theRefusalSendsAXProbingToInspect() throws {
        let repo = try Repo(walkbook: true)

        let reason = try Self.reason(in: #require(repo.hook("xcrun simctl io booted screenshot a.png")))

        #expect(reason.contains("For a one-off capture, re-run `simctl io booted screenshot a.png`, alone or beside anything but another simulator command: the allowance is keyed on that command's own words, so it goes through."))
        #expect(reason.contains("For AX probing, `simwalk inspect --device <udid> --app <bundle id>`"))
    }

    /// Without a walkbook there is nothing better to offer, so the hook is silent.
    @Test
    func withoutAWalkbookTheHookIsSilent() throws {
        let repo = try Repo(walkbook: false)

        #expect(repo.hook("xcrun simctl io booted screenshot a.png") == nil)
    }

    /// The refusal promises the identical re-run goes through, and it does — spacing aside.
    @Test
    func theIdenticalReRunGoesThrough() throws {
        let repo = try Repo(walkbook: true)

        let first = repo.hook("simctl ui booted appearance dark")
        let second = repo.hook("simctl  ui booted appearance   dark")

        #expect(first != nil)
        #expect(second == nil)
    }

    /// Every other command, and this tool itself, goes through untouched.
    @Test(arguments: [
        "ls",
        "xcrun simctl boot booted",
        "echo xcrun simctl io booted screenshot a.png",
        "simwalk walk Docs/Walkbooks/x.json && xcrun simctl io booted screenshot a.png",
        "axe --version",
    ])
    func anythingElseGoesThrough(_ command: String) throws {
        let repo = try Repo(walkbook: true)

        #expect(repo.hook(command) == nil)
    }

    /// AX probing is legitimate (SimWalk#12) and is never nudged, even where a walkbook already covers the screen — only a tap or a screenshot by hand is (SimWalk#37 item 3).
    @Test
    func axeDescribeUIIsNeverNudged() throws {
        let repo = try Repo(walkbook: true)

        #expect(repo.hook("axe describe-ui") == nil)
    }

    /// Forms a plain `simctl io … screenshot` match misses, which still drive a simulator by hand (SimWalk#37 item 2).
    @Test(arguments: [
        "xcrun --sdk iphonesimulator simctl io booted screenshot a.png",
        "timeout 30 xcrun simctl io booted screenshot a.png",
        #"bash -c "xcrun simctl io booted screenshot a.png""#,
        "for i in 1 2 3; do xcrun simctl io booted screenshot a.png; done",
        "axe tap 100 200",
    ])
    func handDrivingFormsTheMatcherUsedToMiss(_ command: String) throws {
        let repo = try Repo(walkbook: true)

        #expect(repo.hook(command) != nil)
    }

    /// A walkbook at the root of the working tree serves a session standing below it, spelled from where the session stands.
    @Test
    func awalkbookAtTheRootServesASubdirectory() throws {
        let repo = try Repo(walkbook: true)
        let below = repo.root.appendingPathComponent("Sources/App", isDirectory: true)
        try FileManager.default.createDirectory(at: below, withIntermediateDirectories: true)

        #expect(RepositoryWalkbooks.loaded(from: below.path).map(\.path) == ["../../Docs/Walkbooks/x.json"])
    }

    /// The price is counted off the walkbook: its screens, and every state across them.
    @Test
    func thePriceCountsTheWalkbooksScreensAndStates() throws {
        let repo = try Repo(walkbook: true)

        let found = RepositoryWalkbooks.loaded(from: repo.root.path)

        #expect(found == [RepositoryWalkbooks.Found(path: "Docs/Walkbooks/x.json", screens: 2, states: 3)])
    }

    /// A session that has not walked, standing where a walkbook is, is told so on its status line; one standing anywhere else still sees nothing.
    @Test
    func thestatusLineSaysAWalkbookIsHereAndUnused() throws {
        let repo = try Repo(walkbook: true)
        let elsewhere = try Repo(walkbook: false)
        let transcript = repo.scratch.url.appendingPathComponent("session.jsonl")
        try TranscriptFixture.append([TranscriptFixture.toolUse("Bash", ["command": "ls"])], to: transcript)
        let report = StatuslineReport(cacheDirectory: repo.scratch.url.appendingPathComponent("statusline", isDirectory: true))

        #expect(report.segment(transcriptPath: transcript.path, workingDirectory: repo.root.path) == "simwalk 0 walks · walkbook here")
        #expect(report.segment(transcriptPath: transcript.path, workingDirectory: elsewhere.root.path) == nil)
        #expect(report.segment(transcriptPath: transcript.path) == nil)
    }

    /// **SimWalk#80, the three calls as they were made.** A compound call is refused, and the screenshot in it is what the allowance is keyed on: the re-run that dropped an `ls` goes through, and so does the screenshot alone with the device spelled out — both were refused when the whole command line was the key.
    @Test
    func theScreenshotInACompoundCallGoesThroughAloneOrBesideAnythingElse() throws {
        let repo = try Repo(walkbook: true)
        let build = #"(sift run -- xcodebuild -scheme App -destination "platform=iOS Simulator,id=$U" build > .build/build.out 2>&1 &)"#

        let first = repo.hook("U=66DE-2B0A && \(build); xcrun simctl io $U screenshot /tmp/h1.png; ls /Applications/Xcode*.app -d; which simwalk cliclick")
        let reRun = repo.hook("U=66DE-2B0A && \(build); xcrun simctl io $U screenshot /tmp/h1.png; which simwalk cliclick")
        let alone = repo.hook("xcrun simctl io 66DE-2B0A screenshot /tmp/h1.png")

        let reason = try Self.reason(in: #require(first))

        #expect(reason.contains("re-run `simctl io 66DE-2B0A screenshot /tmp/h1.png`, alone or beside anything but another simulator command: the allowance is keyed on that command's own words"))
        #expect(reRun == nil)
        #expect(alone == nil)
    }

    /// The allowance is the refused command's alone: a screenshot of another device, or to another file, keys a different call, as does one whose `$NAME` the call never set.
    @Test(arguments: [
        "xcrun simctl io 0000-OTHER screenshot /tmp/h1.png",
        "xcrun simctl io 66DE-2B0A screenshot /tmp/h2.png",
        "xcrun simctl io $U screenshot /tmp/h1.png",
    ])
    func aDifferentSimulatorCommandKeysADifferentCall(_ command: String) throws {
        let repo = try Repo(walkbook: true)

        let refused = try repo.key(of: "U=66DE-2B0A; make build & xcrun simctl io $U screenshot /tmp/h1.png")

        #expect(try repo.key(of: command) != refused)
    }

    /// A `$` the call does not resolve (a loop variable, `$(…)`) stands for something it does not spell, so a different command must not share the key: the whole command line keys the call, as it did before #80.
    @Test(arguments: [
        ("for d in A; do xcrun simctl io $d screenshot /tmp/$d.png; done", "for d in B C; do xcrun simctl io $d screenshot /tmp/$d.png; done"),
        (#"U=$(xcrun simctl list booted); xcrun simctl io "$U" screenshot a.png"#, #"U=$(cat other); xcrun simctl io "$U" screenshot a.png"#),
    ])
    func anUnresolvedVariableKeysTheWholeCommandLine(_ first: String, _ second: String) throws {
        let repo = try Repo(walkbook: true)

        #expect(repo.hook(first) != nil)
        #expect(repo.hook(first) == nil)
        #expect(try repo.key(of: second) != repo.key(of: first))
    }

    /// **SimWalk#110, the five captures.** A one-off screenshot goes through on the first try; a second, different one is refused once; its identical re-run goes through; and the context is then quiet.
    @Test
    func aContextsFirstHandDrivingCallGoesThroughAndItsSecondIsRefusedOnce() throws {
        let repo = try Repo(walkbook: true, seen: false)

        #expect(repo.hook("xcrun simctl io booted screenshot a.png") == nil)
        #expect(repo.hook("xcrun simctl io booted screenshot b.png") != nil)
        #expect(repo.hook("xcrun simctl io booted screenshot b.png") == nil)
        #expect(repo.hook("xcrun simctl io booted screenshot c.png") == nil)
    }

    /// The re-run of a context's first call is not a distinct call: it goes through, however often it is repeated (SimWalk#110 review).
    @Test
    func theReRunOfAContextsFirstCallGoesThrough() throws {
        let repo = try Repo(walkbook: true, seen: false)

        #expect(repo.hook("xcrun simctl io booted screenshot a.png") == nil)
        #expect(repo.hook("xcrun simctl io booted screenshot a.png") == nil)
        #expect(repo.hook("xcrun simctl io booted screenshot a.png") == nil)
    }

    /// Another session has not been told anything: its own first call goes through, and its second is refused though the first context is quiet.
    @Test
    func anotherContextIsIndependent() throws {
        let repo = try Repo(walkbook: true, seen: false)

        #expect(repo.hook("xcrun simctl io booted screenshot a.png") == nil)
        #expect(repo.hook("xcrun simctl io booted screenshot b.png") != nil)
        #expect(repo.hook("xcrun simctl io booted screenshot a.png", session: "s2") == nil)
        #expect(repo.hook("xcrun simctl io booted screenshot b.png", session: "s2") != nil)
    }

    private static func reason(in output: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> String {
        let object = try #require(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any], sourceLocation: sourceLocation)
        let specific = try #require(object["hookSpecificOutput"] as? [String: Any], sourceLocation: sourceLocation)
        return try #require(specific["permissionDecisionReason"] as? String, sourceLocation: sourceLocation)
    }
}

private extension HandDrivingNudgeTests {
    /// A git working tree in scratch, with or without a two-screen, three-state walkbook, and a ledger of its own.
    struct Repo {
        let scratch: TemporaryDirectory

        /// `seen` makes the context's first hand-driving call already, since a first call is let through (SimWalk#110) and most tests are about the refusal after it.
        init(walkbook: Bool, seen: Bool = true) throws {
            scratch = try TemporaryDirectory()
            try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
            guard walkbook else { return }
            defer {
                if seen {
                    _ = hook("xcrun simctl io booted screenshot first-call.png")
                }
            }
            let folder = root.appendingPathComponent("Docs/Walkbooks", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(Self.walkbook.utf8).write(to: folder.appendingPathComponent("x.json"))
        }

        var root: URL {
            scratch.url.appendingPathComponent("repo", isDirectory: true)
        }

        /// What the hook prints for `command`, run as one session's shell call from the repository's root.
        func hook(_ command: String, session: String = "s1") -> String? {
            let payload: [String: Any] = ["session_id": session, "tool_name": "Bash", "tool_input": ["command": command], "cwd": root.path]
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
            return PreToolUseHook.handle(
                data,
                attribution: CallAttribution(directory: scratch.url.appendingPathComponent("callers")),
                nudges: NudgeLedger(directory: scratch.url.appendingPathComponent("nudges"))
            )
        }

        /// The ledger key a refusal of `command` is recorded under, read from the record in a context of its own: what the identical re-run is recognised by.
        func key(of command: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> String {
            let session = "key-\(UUID().uuidString)"
            _ = hook("xcrun simctl io booted screenshot key-primer.png", session: session)
            _ = try #require(hook(command, session: session), sourceLocation: sourceLocation)
            let directory = scratch.url.appendingPathComponent("nudges/\(session)")
            let records = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { !$0.hasPrefix("seen-") }
            return try String(contentsOf: directory.appendingPathComponent(#require(records.first, sourceLocation: sourceLocation)), encoding: .utf8)
        }

        static var walkbook: String {
            """
            {"name": "x", "appBundleID": "com.example.app", "screens": [
              {"id": "home", "route": [{"tab": {"label": "Home"}}], "states": [{"theme": "light"}, {"theme": "dark"}]},
              {"id": "settings", "route": [{"tab": {"label": "Settings"}}], "states": [{"theme": "light"}]}
            ]}
            """
        }
    }
}
