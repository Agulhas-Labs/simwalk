//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
@testable import SimWalkMCP
import SimWalkTestSupport
import Testing

/// A bounded client's walk outlives the call that started it (`Docs/Reference.md`, "Bounded walks", the acceptance list): every wait on a manual clock, the walk a fake held by gates.
struct BoundedWalkTests {
    private typealias Rig = BoundedServerRig

    private static let budget = BoundedServerRig.budget

    // MARK: A walk past its budget

    @Test
    func aWalkLastingTwoAndAHalfBudgetsAnswersRunningThenProgressThenItsAnswer() async throws {
        try await Rig.run(Rig.FakeWalk(advances: true)) { rig in
            try rig.callWalk(id: 2)
            try await rig.clock.advanceOnceSleeping(by: Self.budget)
            let call = try await rig.next()
            let handle = try Self.handle(of: call)
            rig.open(.advance)
            try await rig.until(.advanced)
            try rig.poll(id: 3, handle)
            try await rig.clock.advanceOnceSleeping(by: Self.budget)
            let poll1 = try await rig.next()
            try rig.poll(id: 4, handle)
            try await rig.clock.advanceOnceSleeping(by: Self.budget / 2)
            rig.open(.end)
            let poll2 = try await rig.next()

            #expect(handle == "fake@\(getpid())-1700000000123")
            #expect(call["id"] as? Int == 2)
            #expect(MCPExchange.text(of: call) == "running — \(handle): running, step 2/5 home, 0 failed, 0 of 5 passed; call walk_status with this handle")
            #expect(!MCPExchange.isError(call))
            #expect(poll1["id"] as? Int == 3)
            #expect(MCPExchange.text(of: poll1) == "running — \(handle): running, step 3/5, 0 failed, 0 of 5 passed; call walk_status with this handle")
            #expect(!MCPExchange.isError(poll1))
            #expect(poll2["id"] as? Int == 4)
            #expect(MCPExchange.text(of: poll2) == MCPExchange.answer.text)
            #expect(!MCPExchange.isError(poll2))
        }
    }

    @Test
    func aPollOfAHandleWhoseStemALaterRunReclaimedIsRefusedAsReplaced() async throws {
        let directory = try TemporaryDirectory()
        var old = ""
        try await Rig.run(directory: directory) { rig in
            old = try await Self.runningHandle(rig)
            rig.open(.end)
            try await rig.until(.returned)
        }
        try await Rig.run(Rig.FakeWalk(startedAt: Date(timeIntervalSince1970: 1_700_000_100.456)), directory: directory) { rig in
            let later = try await Self.runningHandle(rig)
            try rig.poll(id: 3, old)
            let poll = try await rig.next()

            #expect(later == "fake@\(getpid())-1700000100456")
            #expect(MCPExchange.text(of: poll) == "refused — the walk \(old) was replaced by a later run under fake")
            #expect(MCPExchange.isError(poll))
        }
    }

    @Test
    func aSecondPollReturnsTheSameHeldAnswerEvenWithItsFileGone() async throws {
        try await Rig.run { rig in
            let handle = try await Self.runningHandle(rig)
            rig.open(.end)
            try await rig.until(.returned)
            try rig.poll(id: 3, handle)
            let first = try await rig.next()
            try FileManager.default.removeItem(at: Self.progressURL("fake", in: rig))
            try rig.poll(id: 4, handle)
            let second = try await rig.next()

            #expect(MCPExchange.text(of: first) == MCPExchange.answer.text)
            #expect(MCPExchange.text(of: second) == MCPExchange.text(of: first))
            #expect(!MCPExchange.isError(second))
        }
    }

    @Test
    func aWalkCancelledBeforeItsHandleIsNamedByTheBusyRefusalAndPollsAfterwards() async throws {
        try await Rig.run(Rig.FakeWalk(holdsBegin: true)) { rig in
            try rig.callWalk(id: 2)
            try await rig.clock.untilSleeping()
            try rig.send(["jsonrpc": "2.0", "method": "notifications/cancelled", "params": ["requestId": 2, "reason": "test"]])
            try rig.callWalk(id: 3)
            rig.open(.begin)
            let busy = try await rig.next()
            let handle = try #require(MCPExchange.text(of: busy)?.firstMatch(of: #/\((\S+)\)/#)?.1)
            rig.clock.advance(by: Self.budget)
            try rig.poll(id: 4, handle)
            try await rig.clock.untilSleeping()
            rig.open(.end)
            let poll = try await rig.next()
            try rig.closeInput()
            let exited = await rig.serverExits()

            #expect(busy["id"] as? Int == 3)
            #expect(MCPExchange.text(of: busy) == "refused — a walk is running (fake@\(getpid())-1700000000123); poll it with walk_status, then retry")
            #expect(MCPExchange.isError(busy))
            #expect(poll["id"] as? Int == 4)
            #expect(MCPExchange.text(of: poll) == MCPExchange.answer.text)
            #expect(exited)
            #expect(rig.remaining().isEmpty, "the cancelled call answers nothing")
        }
    }

    /// The second walk is cancelled while it waits for the first one's handle: it is not answered, not even busy, and logs nothing.
    ///
    /// Reusing its id afterwards is the probe for the cancel being consumed: one left among the cancels ahead would silence the poll.
    @Test
    func aWalkCancelledWhileItWaitsBehindAWalkWithoutAHandleAnswersNothingAndLogsNothing() async throws {
        try await Rig.run(Rig.FakeWalk(holdsBegin: true)) { rig in
            try rig.callWalk(id: 2)
            try await rig.clock.untilSleeping()
            try rig.callWalk(id: 3)
            try rig.send(["jsonrpc": "2.0", "method": "notifications/cancelled", "params": ["requestId": 3, "reason": "test"]])
            try rig.send(MCPExchange.call(id: 4, tool: "validate", arguments: ["walkbook": "book.json"]))
            let validate = try await rig.next()
            rig.open(.begin)
            rig.open(.end)
            try await rig.until(.returned)
            let walk = try await rig.next()
            try rig.poll(id: 3, "fake@\(getpid())-1700000000123")
            let poll = try await rig.next()
            try rig.closeInput()
            let exited = await rig.serverExits()
            let usage = try String(contentsOf: rig.directory.url.appendingPathComponent("usage.jsonl"), encoding: .utf8)

            #expect(validate["id"] as? Int == 4, "the cancel was read before the first walk got its handle")
            #expect(walk["id"] as? Int == 2)
            #expect(poll["id"] as? Int == 3)
            #expect(MCPExchange.text(of: poll) == MCPExchange.answer.text)
            #expect(exited)
            #expect(rig.remaining().isEmpty)
            #expect(!usage.contains("a walk is running"), "the cancelled call logs no busy refusal")
        }
    }

    @Test
    func theEndedBeforeReturnedRaceGetsTheHeldAnswerNeverTheFiles() async throws {
        try await Rig.run(Rig.FakeWalk(endsFileFirst: true)) { rig in
            try rig.callWalk(id: 2)
            try await rig.until(.endedFile)
            try await rig.clock.advanceOnceSleeping(by: Self.budget)
            let call = try await rig.next()
            let handle = try Self.handle(of: call)
            try rig.poll(id: 3, handle)
            try await rig.clock.untilSleeping()
            rig.open(.end)
            let poll = try await rig.next()

            #expect(MCPExchange.text(of: call) == "running — \(handle): finishing, step 2/5 home, 0 failed, 0 of 5 passed; call walk_status with this handle")
            #expect(MCPExchange.text(of: poll) == MCPExchange.answer.text)
            #expect(!MCPExchange.isError(poll))
        }
    }

    // MARK: The busy rule and the free actor

    @Test
    func aSecondWalkDuringABoundedWalkIsRefusedBusy() async throws {
        try await Rig.run { rig in
            try rig.callWalk(id: 2)
            try await rig.until(.began)
            try rig.callWalk(id: 3)
            let busy = try await rig.next()

            #expect(busy["id"] as? Int == 3)
            #expect(MCPExchange.text(of: busy) == "refused — a walk is running (fake@\(getpid())-1700000000123); poll it with walk_status, then retry")
            #expect(MCPExchange.isError(busy))
        }
    }

    @Test
    func aValidateSentWhileABoundedWalkWaitsIsAnsweredBeforeTheBudgetRunsOut() async throws {
        try await Rig.run { rig in
            try rig.callWalk(id: 2)
            try await rig.clock.untilSleeping()
            try rig.send(MCPExchange.call(id: 3, tool: "validate", arguments: ["walkbook": "book.json"]))
            let validate = try await rig.next()

            #expect(validate["id"] as? Int == 3)
            #expect(MCPExchange.text(of: validate) == MCPExchange.answer.text)
            #expect(rig.clock.now == 0, "the budget never moved")
        }
    }

    @Test
    func atEOFMidWalkTheServerExitsOnlyAfterTheWalkEnds() async throws {
        try await Rig.run { rig in
            try rig.callWalk(id: 2)
            try await rig.until(.began)
            try await rig.clock.untilSleeping()
            try rig.closeInput()
            rig.clock.advance(by: Self.budget)
            let call = try await rig.next()
            let exitedEarly = await rig.serverExits(within: 0.3)
            rig.open(.end)
            let exited = await rig.serverExits()

            #expect(MCPExchange.text(of: call)?.hasPrefix("running — fake@") == true)
            #expect(!exitedEarly)
            #expect(exited)
            #expect(rig.events.value.serverExitedAfterWalk)
        }
    }

    // MARK: Claude Code, blocking

    @Test
    func claudeCodeIsAnsweredASecondCallSentDuringAWalkAfterTheWalksAnswer() async throws {
        try await Rig.run(client: "claude-code") { rig in
            try rig.callWalk(id: 2)
            try await rig.until(.began)
            try rig.send(MCPExchange.call(id: 3, tool: "validate", arguments: ["walkbook": "book.json"]))
            let heldBack = await rig.staysQuiet(for: 0.3)
            rig.open(.end)
            let walk = try await rig.next()
            let validate = try await rig.next()

            #expect(heldBack)
            #expect(walk["id"] as? Int == 2)
            #expect(MCPExchange.text(of: walk) == MCPExchange.answer.text)
            #expect(validate["id"] as? Int == 3)
        }
    }

    // MARK: Another server's walk, from its files

    @Test
    func anotherServersEndedWalkIsAnsweredWithItsHeaderVerdictWordAndIsError() async throws {
        try await Rig.run { rig in
            let path = try Self.writeResult(in: rig)
            let handle = try Self.writeProgress(in: rig, phase: .done, resultPath: path)
            try rig.poll(id: 3, handle)
            let poll = try await rig.next()

            #expect(MCPExchange.text(of: poll) == "walk: 'smoke'  app: com.example.app  device: iPhone 17 (26.0)\nqualified — 1 failed, 2 of 3 matched\nresult: \(path)")
            #expect(!MCPExchange.isError(poll))
        }
    }

    @Test
    func aFinishedDryRunIsOkAndNotAnError() async throws {
        try await Rig.run { rig in
            let handle = try Self.writeProgress(in: rig, tool: "walk --dry-run", phase: .done)
            try rig.poll(id: 3, handle)
            let poll = try await rig.next()

            #expect(MCPExchange.text(of: poll) == "ok — the dry run \(handle) finished; a dry run keeps no result file")
            #expect(!MCPExchange.isError(poll))
        }
    }

    @Test
    func aSessionsHandleIsRefusedAsNotAWalk() async throws {
        try await Rig.run { rig in
            let handle = try Self.writeProgress(in: rig, tool: "session", phase: .running)
            try rig.poll(id: 3, handle)
            let poll = try await rig.next()

            #expect(MCPExchange.text(of: poll) == "refused — \(handle) is a live session, not a walk")
            #expect(MCPExchange.isError(poll))
        }
    }

    @Test
    func aServerKilledMidWalkIsAnsweredAtOnceFromANewServerWithTheExitedRefusal() async throws {
        let dead = Process()
        dead.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try dead.run()
        dead.waitUntilExit()

        try await Rig.run { rig in
            let handle = try Self.writeProgress(in: rig, phase: .running, pid: dead.processIdentifier)
            try rig.poll(id: 3, handle)
            let poll = try await rig.next()

            #expect(MCPExchange.text(of: poll) == "refused — the walk \(handle) ended without finishing: the process running it exited")
            #expect(MCPExchange.isError(poll))
            #expect(rig.clock.now == 0, "answered without waiting")
        }
    }

    @Test
    func aWalkThatEndedWithoutAResultFileAndIsNotADryRunIsRefused() async throws {
        try await Rig.run { rig in
            let handle = try Self.writeProgress(in: rig, phase: .done)
            try rig.poll(id: 3, handle)
            let poll = try await rig.next()

            #expect(MCPExchange.text(of: poll) == "refused — the walk \(handle) ended but its result file was not written")
            #expect(MCPExchange.isError(poll))
        }
    }

    // MARK: Bounded walks: the behaviour SimWalk#152 found unpinned

    /// A walk ending on the tick the budget lapses is answered either way the race falls, and never lost: the call gets the ended answer (the expiry re-checks the walk) or the `running` line, and a poll gets the held answer.
    ///
    /// Which of the two it is depends on whether the walk's thread has set its end before the call's task re-checks, so the test pins the two outcomes and what follows them, not one winner.
    @Test
    func aWalkEndingOnTheTickTheBudgetLapsesIsAnsweredEitherWayAndItsAnswerIsHeldForAPoll() async throws {
        try await Rig.run { rig in
            try rig.callWalk(id: 2)
            try await rig.clock.untilSleeping()
            rig.open(.end)
            rig.clock.advance(by: Self.budget)
            let call = try await rig.next()
            try rig.poll(id: 3, "fake@\(getpid())-1700000000123")
            let poll = try await rig.next()
            let text = try #require(MCPExchange.text(of: call))

            #expect(call["id"] as? Int == 2)
            #expect(text == MCPExchange.answer.text || text == "running — fake@\(getpid())-1700000000123: running, step 2/5 home, 0 failed, 0 of 5 passed; call walk_status with this handle")
            #expect(!MCPExchange.isError(call))
            #expect(poll["id"] as? Int == 3)
            #expect(MCPExchange.text(of: poll) == MCPExchange.answer.text)
        }
    }

    /// With the budget cut-off out of play (a walk that ends before it), a bounded client's call blocks to the end and answers the walk's answer, as `claude-code`'s does.
    @Test
    func aBoundedWalkEndingBeforeTheBudgetIsAnsweredInTheOneCallWithoutTheClockMoving() async throws {
        try await Rig.run { rig in
            try rig.callWalk(id: 2)
            try await rig.until(.began)
            rig.open(.end)
            let call = try await rig.next()

            #expect(call["id"] as? Int == 2)
            #expect(MCPExchange.text(of: call) == MCPExchange.answer.text)
            #expect(!MCPExchange.isError(call))
            #expect(rig.clock.now == 0, "the budget never moved")
        }
    }

    /// `session` and `mirror` touch the device as `walk` does, so they meet the same busy refusal; `validate` (above) does not.
    @Test
    func aSessionOrMirrorCallDuringABoundedWalkIsRefusedBusy() async throws {
        try await Rig.run { rig in
            try rig.callWalk(id: 2)
            try await rig.until(.began)
            try rig.send(MCPExchange.call(id: 3, tool: "session", arguments: ["action": "list"]))
            let session = try await rig.next()
            try rig.send(MCPExchange.call(id: 4, tool: "mirror", arguments: ["action": "menu", "item": "home"]))
            let mirror = try await rig.next()
            let busy = "refused — a walk is running (fake@\(getpid())-1700000000123); poll it with walk_status, then retry"

            #expect(session["id"] as? Int == 3)
            #expect(MCPExchange.text(of: session) == busy)
            #expect(MCPExchange.isError(session))
            #expect(mirror["id"] as? Int == 4)
            #expect(MCPExchange.text(of: mirror) == busy)
            #expect(MCPExchange.isError(mirror))
        }
    }

    /// A walk cancelled once its call has the handle (the call waiting out its budget) is not answered at the budget, and the walk goes on to its answer for a poll.
    @Test
    func aWalkCancelledAfterItsHandleAnswersNothingAtTheBudgetAndPollsAfterwards() async throws {
        try await Rig.run { rig in
            try rig.callWalk(id: 2)
            try await rig.until(.began)
            try await rig.clock.untilSleeping()
            try rig.send(["jsonrpc": "2.0", "method": "notifications/cancelled", "params": ["requestId": 2, "reason": "test"]])
            try rig.send(MCPExchange.call(id: 3, tool: "validate", arguments: ["walkbook": "book.json"]))
            let validate = try await rig.next()
            rig.clock.advance(by: Self.budget)
            let quiet = await rig.staysQuiet(for: 0.3)
            try rig.poll(id: 4, "fake@\(getpid())-1700000000123")
            try await rig.clock.untilSleeping()
            rig.open(.end)
            let poll = try await rig.next()

            #expect(validate["id"] as? Int == 3, "the cancel was read before the budget lapsed")
            #expect(quiet, "the cancelled call answers nothing at the budget")
            #expect(poll["id"] as? Int == 4)
            #expect(MCPExchange.text(of: poll) == MCPExchange.answer.text)
            #expect(rig.remaining().isEmpty)
        }
    }

    /// A `walk_status` cancelled ahead of its start is not answered, logs nothing, and leaves no id behind: the held answer is still there for the next poll, which may reuse the id.
    @Test
    func aCancelledWalkStatusIsNotAnsweredLogsNothingAndConsumesNothing() async throws {
        try await Rig.run { rig in
            let handle = try await Self.runningHandle(rig)
            try rig.send(["jsonrpc": "2.0", "method": "notifications/cancelled", "params": ["requestId": 3, "reason": "test"]])
            try rig.send(MCPExchange.call(id: 4, tool: "validate", arguments: ["walkbook": "book.json"]))
            let validate = try await rig.next()
            try rig.poll(id: 3, handle)
            rig.open(.end)
            try await rig.until(.returned)
            let quiet = await rig.staysQuiet(for: 0.3)
            let usageFile = rig.directory.url.appendingPathComponent("usage.jsonl")
            let before = try String(contentsOf: usageFile, encoding: .utf8)
            try rig.poll(id: 3, handle)
            let poll = try await rig.next()
            let after = try String(contentsOf: usageFile, encoding: .utf8)

            #expect(validate["id"] as? Int == 4)
            #expect(quiet, "the cancelled poll answers nothing")
            #expect(!before.contains("walk_status"), "the cancelled poll logs nothing")
            #expect(poll["id"] as? Int == 3)
            #expect(MCPExchange.text(of: poll) == MCPExchange.answer.text)
            #expect(after.contains("walk_status"), "the id was not left cancelled for the next call")
        }
    }

    /// A `walk_status` cancelled while it waits out its budget is not answered and writes no usage line, and leaves no id behind: the next poll under the same id is answered and logged.
    @Test
    func aWalkStatusCancelledDuringItsWaitIsNotAnsweredLogsNothingAndConsumesNothing() async throws {
        try await Rig.run { rig in
            let handle = try await Self.runningHandle(rig)
            try rig.poll(id: 3, handle)
            try await rig.clock.untilSleeping()
            try rig.send(["jsonrpc": "2.0", "method": "notifications/cancelled", "params": ["requestId": 3, "reason": "test"]])
            try rig.send(MCPExchange.call(id: 4, tool: "validate", arguments: ["walkbook": "book.json"]))
            let validate = try await rig.next()
            rig.clock.advance(by: Self.budget)
            let quiet = await rig.staysQuiet(for: 0.3)
            let usageFile = rig.directory.url.appendingPathComponent("usage.jsonl")
            let before = try String(contentsOf: usageFile, encoding: .utf8)
            rig.open(.end)
            try await rig.until(.returned)
            try rig.poll(id: 3, handle)
            let poll = try await rig.next()
            let after = try String(contentsOf: usageFile, encoding: .utf8)

            #expect(validate["id"] as? Int == 4)
            #expect(quiet, "the cancelled poll answers nothing at its budget")
            #expect(!before.contains("walk_status"), "the cancelled poll logs nothing")
            #expect(poll["id"] as? Int == 3)
            #expect(MCPExchange.text(of: poll) == MCPExchange.answer.text)
            #expect(after.contains("walk_status"), "the id was not left cancelled for the next call")
        }
    }

    /// A bounded walk's usage line is written when the walk ends and spans the walk itself in wall time: the budget, which the injected clock moved by 10 s, is not what it measures.
    @Test
    func aBoundedWalksUsageLineRecordsTheWalksWholeDurationNotTheBudget() async throws {
        try await Rig.run { rig in
            let handle = try await Self.runningHandle(rig)
            let held = await rig.staysQuiet(for: 0.3)
            rig.open(.end)
            try rig.poll(id: 3, handle)
            _ = try await rig.next()
            let usage = try String(contentsOf: rig.directory.url.appendingPathComponent("usage.jsonl"), encoding: .utf8)
            let walkLine = try #require(usage.split(separator: "\n").compactMap { line in
                try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }.first { $0["tool"] as? String == "walk" })
            let milliseconds = try #require(walkLine["ms"] as? Int)

            #expect(held)
            #expect(milliseconds >= 250, "the line covers the walk's 0.3 s, past the call's answer at the budget")
            #expect(milliseconds < Int(Self.budget * 1000), "the injected clock's budget is not what is measured")
        }
    }
}

private extension BoundedWalkTests {
    static let startedAt = Date(timeIntervalSince1970: 1_700_000_000.123)

    /// The handle a `running` line names.
    static func handle(of response: [String: Any], sourceLocation: SourceLocation = #_sourceLocation) throws -> String {
        try String(#require(MCPExchange.text(of: response)?.firstMatch(of: #/^running — (\S+): /#)?.1, sourceLocation: sourceLocation))
    }

    /// Starts a walk, lets its call's budget pass, and returns the handle its `running` line names.
    static func runningHandle(_ rig: BoundedServerRig, sourceLocation: SourceLocation = #_sourceLocation) async throws -> String {
        try rig.callWalk(id: 2)
        try await rig.clock.advanceOnceSleeping(by: budget)
        return try await handle(of: rig.next(), sourceLocation: sourceLocation)
    }

    static func progressURL(_ stem: String, in rig: BoundedServerRig) -> URL {
        ProgressLocation.progressURL(session: stem, in: rig.directory.url)
    }

    /// Writes `other.json` as another server's walk left it and returns its handle.
    static func writeProgress(
        in rig: BoundedServerRig,
        tool: String = "walk",
        phase: WalkProgress.Phase,
        pid: Int32 = getpid(),
        resultPath: String? = nil
    ) throws -> String {
        var progress = WalkProgress(tool: tool, phase: phase, pid: pid, startedAt: startedAt)
        progress.resultPath = resultPath
        let url = progressURL("other", in: rig)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try WalkProgress.encoder().encode(progress).write(to: url)
        return WalkHandle(stem: "other", progress: progress).text
    }

    /// Writes `other.result.json`, a walk with one of three screens failed, and returns its path.
    static func writeResult(in rig: BoundedServerRig) throws -> String {
        let result = WalkResult(
            schemaVersion: 1,
            tool: "walk",
            verdict: .failed,
            walkName: "smoke",
            app: "com.example.app",
            device: WalkProgress.Device(name: "iPhone 17", udid: "UDID", osVersion: "26.0"),
            bundlePath: "/tmp/bundle",
            timings: PhaseTimings(),
            counts: WalkResult.Counts(planned: 3, passed: 2, failed: 1),
            steps: [],
            failures: [],
            truncated: WalkResult.Truncated(omittedSteps: 0)
        )
        let url = ProgressLocation.resultURL(session: "other", in: rig.directory.url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try WalkResult.encoder().encode(result).write(to: url)
        return url.path
    }
}
