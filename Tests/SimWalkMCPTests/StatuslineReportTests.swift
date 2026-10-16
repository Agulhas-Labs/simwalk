//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkMCP
import SimWalkTestSupport
import Testing

/// One line of somebody's screen, so what it says has to be exactly true: it counts every call the session made, prices only the calls it can attribute, and says nothing at all when there is nothing to say.
struct StatuslineReportTests {
    /// The two ways of reaching the tool are both counted, and only the one that recorded a session is priced — so the count is honest about the shell call while the saving does not claim for it.
    @Test
    func anmcpCallIsPricedAndAShellCallIsCountedWithoutBeingPriced() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "example.json"]),
            TranscriptFixture.toolUse("Bash", ["command": "simwalk bundle inspect out.simwalk"]),
        ], to: scratch.transcript)
        scratch.log.record(tool: "walk", target: "example.json", milliseconds: 9, succeeded: true, saving: Self.saving, session: scratch.session)
        scratch.log.record(tool: "walk", target: "torn.json", milliseconds: 2, succeeded: false, err: "no such file", session: scratch.session, kind: .inputRefused)

        let segment = scratch.report.segment(transcriptPath: scratch.transcript.path)

        #expect(segment == "simwalk ~17k tokens saved · 2 calls · 1 refused")
    }

    /// The count is named after the verb only when every counted call was that verb, because a walk is the expensive thing and the word a reader takes at face value.
    @Test
    func acountOfNothingButWalksIsWordedAsWalks() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "a.json"]),
            TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "b.json"]),
            TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "c.json"]),
        ], to: scratch.transcript)

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 3 walks")
    }

    /// A dry run captures nothing and costs seconds rather than minutes, so it is counted as a call and never as a walk — worded "calls" here because the session's other call is a real walk.
    @Test
    func admcpDryRunIsCountedButNeverAWalk() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "a.json", "dryRun": true]),
            TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "b.json"]),
        ], to: scratch.transcript)

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 2 calls")
    }

    @Test
    func asessionThatNeverCalledPrintsNothingAtAll() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("Bash", ["command": "swift test"]),
            TranscriptFixture.toolUse("Read", ["file_path": "/tmp/notes.md"]),
            TranscriptFixture.toolResult(id: "a-call-this-scan-never-counted"),
        ], to: scratch.transcript)

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == nil)
    }

    /// **The regression this exists for.** Naming the binary is not calling it: a session that listed the deployed file, replaced it and read its log had never walked anything, and read `simwalk 1 call`.
    ///
    /// The last two are the other half of that: the name is the *whole* last path component, so a neighbour that merely contains it is somebody else's program and never this one's call.
    @Test
    func acommandThatOnlyNamesTheBinaryIsNotACall() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("Bash", ["command": "ls -l ~/.local/bin/sift ~/.local/bin/simwalk"]),
            TranscriptFixture.toolUse("Bash", ["command": "rm ~/.local/bin/simwalk && cp .build/release/simwalk ~/.local/bin/"]),
            TranscriptFixture.toolUse("Bash", ["command": "tail -3 ~/.simwalk/usage.jsonl"]),
            TranscriptFixture.toolUse("Bash", ["command": "simwalk-old walk book.yml"]),
            TranscriptFixture.toolUse("Bash", ["command": "my-simwalk validate x"]),
        ], to: scratch.transcript)

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == nil)
    }

    /// **Adjacency is not command position.** Two words `simwalk <verb>` inside a quoted argument are a sentence about the tool, and a heredoc body is a file being written with the tool's name in it — the installer's own shim among them, so a session debugging the status line by hand read as a session that had walked something.
    ///
    /// The last two are a quote that does not end where it appears to: an escaped `\"` inside a double-quoted argument is a character *of* the argument, and a commit subject quoting a command is ordinary practice here. Reading it as the close of the quote hands the rest of the message to the lexer as shell, where the `;` or `&&` in it opens command position on words that were only ever prose.
    @Test
    func anameInsideAQuotedArgumentOrAHeredocIsNotACall() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("Bash", ["command": "git commit -m \"docs(usage): simwalk usage reads the shared log\""]),
            TranscriptFixture.toolUse("Bash", ["command": "grep -rn \"simwalk walk\" Docs/"]),
            TranscriptFixture.toolUse("Bash", ["command": "cat > ~/.sift/statusline.d/simwalk <<'SH'\n#!/bin/sh\nexec simwalk statusline \"$@\"\nSH"]),
            TranscriptFixture.toolUse("Bash", ["command": "git commit -m \"fix: \\\"simwalk walk\\\" is the call; simwalk usage is too\""]),
            TranscriptFixture.toolUse("Bash", ["command": "echo \"see \\\"docs\\\" && simwalk walk for more\""]),
            TranscriptFixture.toolUse("Bash", ["command": "echo $'don\\'t forget; simwalk walk book.yml'"]),
        ], to: scratch.transcript)

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == nil)
    }

    /// A function body is stored, not run: declaring `run() { simwalk walk book.yml; }` calls nothing, and a session that defined a helper and never used it had made no call at all.
    ///
    /// The brace opening the body on a line of its own is the same declaration, and it follows a separator exactly as a group's brace does — so what tells them apart is the definition one line further back, in each of the three spellings bash accepts.
    @Test
    func afunctionBodyIsStoredRatherThanRun() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("Bash", ["command": "run() { simwalk walk book.yml; }"]),
            TranscriptFixture.toolUse("Bash", ["command": "sw() {\n  simwalk walk \"$@\"\n}"]),
            TranscriptFixture.toolUse("Bash", ["command": "f() (simwalk walk )"]),
            TranscriptFixture.toolUse("Bash", ["command": "sw()\n{\n  simwalk walk\n}"]),
            TranscriptFixture.toolUse("Bash", ["command": "run()\n(\n  simwalk walk book.yml\n)"]),
            TranscriptFixture.toolUse("Bash", ["command": "function sw\n{\n  simwalk walk\n}"]),
        ], to: scratch.transcript)

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == nil)
    }

    /// **A definition that is then called is a call, and this gives it up rather than guessing at it.**
    ///
    /// `main() { simwalk walk; }` followed by `main` really does run a walk — but saying so means resolving the name on the last line back to the body filed under it, which is a shell this does not have. The body is dropped where it is declared, so the walk goes uncounted.
    ///
    /// Recorded as a test rather than left to be discovered, because it is the one shape here where the honest answer and the true one differ. It undercounts, which is the direction this number is allowed to be wrong in — and a later change that counts it *for the right reason* is an improvement this expectation should be updated for, not a regression it should block.
    @Test
    func adefinitionCalledOnALaterLineIsGivenUpRatherThanGuessedAt() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("Bash", ["command": "main()\n{\n  simwalk walk\n}\nmain"]),
        ], to: scratch.transcript)

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == nil)
    }

    /// A group the shell runs is still a group: a `(` or `{` that opens one at the start of a command leaves what follows it in command position, which a function body's brace does not.
    @Test
    func acallInsideAGroupIsStillACall() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("Bash", ["command": "{ simwalk walk; }"]),
            TranscriptFixture.toolUse("Bash", ["command": "(cd /x && simwalk walk b.yml)"]),
            TranscriptFixture.toolUse("Bash", ["command": "echo a; { echo b; }; simwalk walk"]),
            TranscriptFixture.toolUse("Bash", ["command": "ls && { simwalk walk; }"]),
        ], to: scratch.transcript)

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 4 calls")
    }

    /// A comment is text the shell never runs, so nothing in one is a call — and it stays inert only by accident until it carries a separator, which reopens command position on a note somebody left themselves.
    @Test
    func acommentIsTextTheShellNeverRuns() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("Bash", ["command": "ls\n# rebuild; simwalk walk book.yml"]),
            TranscriptFixture.toolUse("Bash", ["command": "swift build\n# simwalk walk a && simwalk walk b"]),
            TranscriptFixture.toolUse("Bash", ["command": "swift build 2>&1 | tail -5  # then: cd /tmp && simwalk walk book.yml"]),
        ], to: scratch.transcript)

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == nil)
    }

    /// A prefix that only decorates the command behind it leaves the binary in command position, so the call is still the call it was — and a prefix is read as one only where it is itself at the front of a command.
    @Test
    func aninvocationBehindAShellPrefixIsStillACall() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("Bash", ["command": "sudo simwalk walk example.json"]),
            TranscriptFixture.toolUse("Bash", ["command": "env SIMWALK_QUIET=1 simwalk usage"]),
            TranscriptFixture.toolUse("Bash", ["command": "time simwalk validate a.json"]),
            TranscriptFixture.toolUse("Bash", ["command": "cd /tmp && swift run simwalk bundle inspect out.simwalk"]),
        ], to: scratch.transcript)

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 4 calls")
    }

    /// An invocation is counted through whatever path reached the binary, since a walk run from an absolute path is the same walk.
    @Test
    func aninvocationIsCountedThroughWhateverPathReachedIt() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("Bash", ["command": "~/.local/bin/simwalk usage --since 7d"]),
            TranscriptFixture.toolUse("Bash", ["command": "\"$HOME/.local/bin/simwalk\" bundle audit out.simwalk | head -1"]),
        ], to: scratch.transcript)

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 2 calls")
    }

    /// A line the CLI wrote carries no session, so nothing about it can be attributed to one — which is the whole reason the shell face records none.
    @Test
    func alogLineWithNoSessionIsNeverClaimedByASession() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("Bash", ["command": "simwalk walk example.json --output out.simwalk"]),
        ], to: scratch.transcript)
        scratch.log.record(tool: "walk", target: "example.json", milliseconds: 9, succeeded: true, saving: Self.saving)

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 1 call")
    }

    /// The log is shared by every session on the machine, so a saving that is not this session's must not be taken — the one direction a saving must never round.
    @Test
    func anotherSessionsSavingIsNotClaimed() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("mcp__simwalk__validate", ["walkbook": "a.json"]),
        ], to: scratch.transcript)
        scratch.log.record(tool: "walk", target: "b.json", milliseconds: 9, succeeded: false, err: "boom", saving: Self.saving, session: "somebody-else")

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 1 call")
    }

    /// A subagent's walk is still this session's walk, and its transcript is a file of its own beside the session's.
    @Test
    func asubagentsCallsAreCountedWithTheSessionsOwn() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "a.json"])], to: scratch.transcript)
        let subagents = scratch.transcript.deletingPathExtension().appendingPathComponent("subagents", isDirectory: true)
        try FileManager.default.createDirectory(at: subagents, withIntermediateDirectories: true)
        try TranscriptFixture.append(
            [TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "b.json"])],
            to: subagents.appendingPathComponent("agent-1.jsonl")
        )

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 2 walks")
    }

    /// The scan is incremental — each render reads only what was appended — so the second render has to reach the same total the first would have had it seen everything.
    @Test
    func asecondRenderCountsWhatWasAppendedSinceTheFirst() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "a.json"])], to: scratch.transcript)
        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 1 walk")

        try TranscriptFixture.append([TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "b.json"])], to: scratch.transcript)
        scratch.log.record(tool: "walk", target: "b.json", milliseconds: 9, succeeded: true, saving: Self.saving, session: scratch.session)

        let cached = scratch.cacheDirectory.appendingPathComponent("\(scratch.session).json")

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk ~17k tokens saved · 2 walks")
        #expect(FileManager.default.fileExists(atPath: cached.path))
    }

    /// **A cached count means whatever the rule that counted it meant.** Only the bytes appended since the last render are ever scanned, so a state written under an older rule would carry its wrong calls for the life of the session — which is why a version it does not recognise is discarded rather than migrated, and why bumping that version is part of changing what a call *is*.
    @Test
    func acacheWrittenUnderAnOlderRuleIsDiscardedRatherThanCarried() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "a.json"]),
            TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "b.json"]),
        ], to: scratch.transcript)
        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 2 walks")

        // The cache as an older version left it: read through to the end of the transcript, so nothing
        // would be scanned again, and holding a tally the transcript does not say.
        var state = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: scratch.cache)) as? [String: Any])
        var entries = try #require(state["entries"] as? [String: [String: Any]])
        var entry = try #require(entries[scratch.transcript.path])
        entry["tally"] = ["calls": 9, "walks": 0]
        entries[scratch.transcript.path] = entry
        state["entries"] = entries
        state["version"] = 2
        try JSONSerialization.data(withJSONObject: state).write(to: scratch.cache)

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 2 walks")
    }

    /// A partial line is the writer being mid-write, and counting it would be counting a call that has not happened — so the scan stops at the last newline and picks the rest up next time.
    @Test
    func ahalfWrittenLineIsLeftForTheNextRender() throws {
        let scratch = try Scratch()
        let complete = try TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "a.json"])
        let partial = try TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "b.json"])
        try Data((complete + "\n" + String(partial.prefix(partial.count / 2))).utf8).write(to: scratch.transcript)
        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 1 walk")

        try Data((complete + "\n" + partial + "\n").utf8).write(to: scratch.transcript)

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 2 walks")
    }

    /// Hiding is a render-time switch, so an upgrade that re-runs the installer cannot resurrect a line somebody silenced.
    @Test
    func ahiddenStatusLinePrintsNothingWhileStayingRegistered() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "a.json"])], to: scratch.transcript)
        let visibility = StatuslineVisibility(cacheDirectory: scratch.cacheDirectory)

        #expect(try visibility.hide())
        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == nil)
        #expect(try visibility.show())
        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 1 walk")
    }

    /// **A call the user denied is not a call the session made.** It is counted where the `tool_use` appears, because that is the first line that can know about it, and taken back when the result says it never ran.
    @Test
    func adeniedCallIsCountedAndThenTakenBack() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("mcp__simwalk__walk", id: "allowed", ["walkbook": "a.json"]),
            TranscriptFixture.toolResult(id: "allowed"),
            TranscriptFixture.toolUse("mcp__simwalk__walk", id: "denied", ["walkbook": "b.json"]),
            TranscriptFixture.toolResult(id: "denied", isError: true, text: TranscriptFixture.denial),
            TranscriptFixture.toolUse("Bash", id: "denied-shell", ["command": "simwalk usage"]),
            TranscriptFixture.toolResult(id: "denied-shell", isError: true, text: TranscriptFixture.denial),
        ], to: scratch.transcript)

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 1 walk")
    }

    /// A walk that *refused* is a call this tool answered, and belongs in the count — which is why a denial is recognised by the answer's own wording rather than by the error flag alone.
    @Test
    func arefusedCallIsStillACallTheSessionMade() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("mcp__simwalk__walk", id: "refused", ["walkbook": "/absent.json"]),
            TranscriptFixture.toolResult(id: "refused", isError: true, text: "refused — cannot read walkbook at /absent.json"),
        ], to: scratch.transcript)
        scratch.log.record(tool: "walk", target: "/absent.json", milliseconds: 2, succeeded: false, err: "no such file", session: scratch.session, kind: .inputRefused)

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 1 walk · 1 refused")
    }

    /// "Failed" and "refused" here mean what `simwalk usage` means by them: a walk that fell over on this tool's own machinery is a failure, and never a refusal — which is a claim about *why* the call failed and would misdirect a reader straight at their own argument.
    ///
    /// (Round three pinned this segment as `simwalk 1 walk`, with the failure shown nowhere: a session whose every walk fell over read as a clean one.)
    @Test
    func afailureThatIsNotInputRefusedIsCountedAsFailedNotRefused() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("mcp__simwalk__walk", id: "failed", ["walkbook": "book.json"]),
            TranscriptFixture.toolResult(id: "failed", isError: true, text: "refused — the walk did not complete: crash"),
        ], to: scratch.transcript)
        scratch.log.record(tool: "walk", target: "book.json", milliseconds: 2, succeeded: false, err: "the walk did not complete: crash", session: scratch.session, kind: .runnerFailed)

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 1 walk · 1 failed")
    }

    /// Both counts, each under its own word, in the order `simwalk usage` puts them — the tool's failures before the caller's refusals — and each left off at zero.
    @Test
    func failedAndRefusedAreCountedApartAndNamedInThatOrder() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "a.json"]),
            TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "b.json"]),
            TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "c.json"]),
        ], to: scratch.transcript)
        scratch.log.record(tool: "walk", target: "a.json", milliseconds: 2, succeeded: false, err: "the walk did not complete: crash", session: scratch.session, kind: .runnerFailed)
        scratch.log.record(tool: "walk", target: "b.json", milliseconds: 2, succeeded: false, err: "vector rejected", session: scratch.session, kind: .toolError)
        scratch.log.record(tool: "walk", target: "c.json", milliseconds: 2, succeeded: false, err: "no such file", session: scratch.session, kind: .inputRefused)

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 3 walks · 2 failed · 1 refused")
    }

    /// A line written with no `kind` — by an MCP server started before the field existed, which a session keeps across a deploy — is read the way `simwalk usage` reads it: classified off its own error text where that is unambiguous, and a failure where it is not.
    ///
    /// Reading the stored field alone would count the first as a failure and hide it from "refused", in exactly the session that crossed the deploy.
    @Test
    func alineWithNoStoredKindIsReadTheWayUsageReadsIt() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "a.json"]),
            TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "b.json"]),
        ], to: scratch.transcript)
        scratch.log.record(tool: "walk", target: "a.json", milliseconds: 2, succeeded: false, err: "cannot read walkbook at a.json: no such file", session: scratch.session)
        scratch.log.record(tool: "walk", target: "b.json", milliseconds: 2, succeeded: false, err: "a mystery nothing classifies", session: scratch.session)

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 2 walks · 1 failed · 1 refused")
    }

    /// A cache written when "refused" counted every failed call is discarded, not carried: only bytes appended since the last render are scanned, so a session that crossed the deploy would otherwise show its runner failures as refusals for the rest of its life.
    @Test
    func acacheCountedUnderTheOldMeaningOfRefusedIsDiscarded() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "a.json"]),
            TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "b.json"]),
            TranscriptFixture.toolUse("mcp__simwalk__walk", ["walkbook": "c.json"]),
        ], to: scratch.transcript)
        for target in ["a.json", "b.json", "c.json"] {
            scratch.log.record(tool: "walk", target: target, milliseconds: 2, succeeded: false, err: "the walk did not complete: crash", session: scratch.session, kind: .runnerFailed)
        }
        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 3 walks · 3 failed")

        // The state as the previous version left it: the log read to its end, and every failure under `refusals`.
        var state = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: scratch.cache)) as? [String: Any])
        var usage = try #require(state["usage"] as? [String: Any])
        usage["refusals"] = 3
        usage["failures"] = 0
        state["usage"] = usage
        state["version"] = 3
        try JSONSerialization.data(withJSONObject: state).write(to: scratch.cache)

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 3 walks · 3 failed")
    }

    /// **The regression this exists for.** A shell `walk` that reached every screen but one exits **2** — a documented success — and Claude Code marks any non-zero exit as an error, so reading only for `refused — ` took the call back and a session whose walks were all qualified showed no status line at all.
    @Test
    func aqualifiedShellCallIsStillACallTheSessionMade() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("Bash", id: "shell", ["command": "simwalk walk example.json --output out.simwalk"]),
            TranscriptFixture.toolResult(
                id: "shell",
                isError: true,
                text: "walk: 'example'  app: com.example.app\nqualified — 1 screen unreachable · 2 of 3 screens captured\n\nExit code 2"
            ),
        ], to: scratch.transcript)

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 1 call")
    }

    /// The same for the verdict a clean call carries, which a shell pipeline can still turn into an errored result.
    @Test
    func anokAnswerIsStillACallTheSessionMade() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append([
            TranscriptFixture.toolUse("Bash", id: "shell", ["command": "simwalk bundle inspect out.simwalk | head -1"]),
            TranscriptFixture.toolResult(id: "shell", isError: true, text: "ok — 1 of 1 screens captured · 3 captures"),
        ], to: scratch.transcript)

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 1 call")
    }

    /// The result almost never lands in the same render as the call, so the ids in flight are part of the cached state — a denial arriving after a resume has to take back a call counted before it.
    @Test
    func adenialLandingAfterAnEarlierRenderStillTakesItsCallBack() throws {
        let scratch = try Scratch()
        try TranscriptFixture.append(
            [TranscriptFixture.toolUse("mcp__simwalk__walk", id: "denied", ["walkbook": "a.json"])],
            to: scratch.transcript
        )
        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == "simwalk 1 walk")

        try TranscriptFixture.append(
            [TranscriptFixture.toolResult(id: "denied", isError: true, text: TranscriptFixture.denial)],
            to: scratch.transcript
        )

        #expect(scratch.report.segment(transcriptPath: scratch.transcript.path) == nil)
    }

    /// One weighing, reused: two screenshots at the iPhone 17 figure and 40 kB of trees, against an 800-byte answer — 8,140 + 10,000 − 200 tokens.
    private static var saving: ContextSaving {
        ContextSaving(screenshotTokens: [4070, 4070], treeBytes: 40000, servedBytes: 800)
    }
}

private extension StatuslineReportTests {
    /// A throwaway `~/.simwalk` with a transcript beside it, so a test never reads the machine's own.
    struct Scratch {
        let directory: TemporaryDirectory
        let session = "session-\(UUID().uuidString)"

        init() throws {
            directory = try TemporaryDirectory()
        }

        var cacheDirectory: URL {
            directory.url.appendingPathComponent("statusline", isDirectory: true)
        }

        var transcript: URL {
            directory.url.appendingPathComponent("\(session).jsonl")
        }

        /// Where a render leaves what it scanned, so a test can put a state of its own there.
        var cache: URL {
            cacheDirectory.appendingPathComponent("\(session).json")
        }

        var log: UsageLog {
            UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        }

        var report: StatuslineReport {
            StatuslineReport(cacheDirectory: cacheDirectory, usageLogURL: log.fileURL)
        }
    }
}
