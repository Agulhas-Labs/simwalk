//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// The value oracle as an external command: a real script, fed JSON lines on stdin, answering one JSON object per line — and every way it can fail answered `oracle failed`, never a match or a mismatch.
struct CommandOracleTests {
    private static var fixtures: URL {
        get throws {
            try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        }
    }

    private static func oracle(_ mode: String, timeout: TimeInterval = CommandOracle.defaultTimeout) throws -> CommandOracle {
        try CommandOracle(Walkbook.Oracle(command: ["/bin/sh", "fixed-oracle.sh", mode]), walkbookDirectory: fixtures, timeout: timeout)
    }

    /// A real app's case end to end: `2,703` read off the capture, asked of the script, matched to the rolling window with midnight's 3326 beside it.
    @Test
    func theExampleFigureMatchesTheRollingWindowThroughARealCommand() throws {
        let directory = try TemporaryDirectory()
        let bundle = try FigureFixture.figureBundle(in: directory)

        let checks = try OracleCheck.checks(of: bundle, against: FigureFixture.figureWalkbook(), oracle: Self.oracle("fixed"))

        #expect(checks.map(\.rendered) == [
            "today/light-loc_en_us steps-today: 2,703 matches rolling24h (exact) — midnight 3326, rolling24h 2703 count — stepCount sum over the seeded store",
        ])
    }

    /// One process answers every request, in order, each line its own answer — an error for one figure fails that figure alone.
    @Test
    func aBatchIsAnsweredLineByLineInRequestOrder() throws {
        let answers = try Self.oracle("fixed").answers(to: [Self.request("distance"), Self.request("unknown"), Self.request("steps-today")])

        #expect(answers == [
            .reply(values: ["midnight": 4.23, "rolling24h": 3.9], unit: "km", attribution: nil),
            .failed(reason: "it answered: no such figure"),
            .reply(values: ["midnight": 3326, "rolling24h": 2703], unit: "count", attribution: "stepCount sum over the seeded store"),
        ])
    }

    @Test
    func aNonZeroExitFailsEveryRequestNamingWhy() throws {
        let answers = try Self.oracle("exit").answers(to: [Self.request("steps-today"), Self.request("distance")])

        #expect(answers == Array(repeating: .failed(reason: "it exited 3: store not seeded"), count: 2))
    }

    @Test
    func anOracleThatDoesNotAnswerInTimeFails() throws {
        let answers = try Self.oracle("sleep", timeout: 0.5).answers(to: [Self.request("steps-today")])

        #expect(answers == [.failed(reason: "it did not answer within 0.5s")])
    }

    /// A timeout stops what the command started as well as the command: the fixture's shell runs `sleep` without `exec`, as a script running `python3 query.py` does, and the sleep is gone once the answer is in.
    @Test
    func anOracleThatTimesOutLeavesNothingItStartedRunning() throws {
        let directory = try TemporaryDirectory()
        let pidFile = directory.url.appendingPathComponent("grandchild.pid")
        let oracle = try CommandOracle(Walkbook.Oracle(command: ["/bin/sh", "fixed-oracle.sh", "grandchild", pidFile.path]), walkbookDirectory: Self.fixtures, timeout: 1)

        let answers = oracle.answers(to: [Self.request("steps-today")])
        let grandchild = try #require(pid_t(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        let gone = Self.isGone(grandchild, within: 2)
        if !gone {
            // Only the sleep this test started, by the pid it wrote.
            kill(grandchild, SIGKILL)
        }

        #expect(answers == [.failed(reason: "it did not answer within 1s")])
        #expect(gone)
    }

    /// The `SIGKILL` reaches the whole group too (SimWalk#64): a grandchild that ignores `SIGTERM`, under a script that does not, is gone once the timeout has been answered — before, the script's death to `SIGTERM` left nothing for the escalation to aim at, and the grandchild outlived the bound.
    @Test
    func anOracleGrandchildThatIgnoresTheRequestToStopIsKilled() throws {
        let directory = try TemporaryDirectory()
        let pidFile = directory.url.appendingPathComponent("grandchild.pid")
        let oracle = try CommandOracle(Walkbook.Oracle(command: ["/bin/sh", "fixed-oracle.sh", "stubborn-grandchild", pidFile.path]), walkbookDirectory: Self.fixtures, timeout: 1)

        let answers = oracle.answers(to: [Self.request("steps-today")])
        let grandchild = try #require(pid_t(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        // A moment, not a bound: an orphan killed is reaped by launchd, and until then `kill(pid, 0)` still answers.
        let gone = Self.isGone(grandchild, within: 2)
        defer {
            if !gone {
                // Only the sleep this test started, by the pid it wrote, and only once it was seen alive.
                kill(grandchild, SIGKILL)
            }
        }

        #expect(answers == [.failed(reason: "it did not answer within 1s")])
        #expect(gone)
    }

    @Test
    func aReplyThatIsNotJSONFailsItsRequest() throws {
        let answers = try Self.oracle("garbage").answers(to: [Self.request("steps-today")])

        #expect(answers == [.failed(reason: "its reply is not a JSON object of values: 'steps: lots'")])
    }

    /// Replies are matched by order, so a short answer is attributed to none of the requests.
    @Test
    func aShortAnswerFailsEveryRequest() throws {
        let answers = try Self.oracle("short").answers(to: [Self.request("steps-today"), Self.request("distance")])

        #expect(answers == Array(repeating: .failed(reason: "it answered 1 line to 2 requests, and replies are matched by order"), count: 2))
    }

    /// A relative executable resolves against the walkbook's directory, not the process's.
    @Test
    func aRelativeCommandResolvesAgainstTheWalkbooksDirectory() throws {
        let directory = try TemporaryDirectory()
        let script = directory.url.appendingPathComponent("oracle.sh")
        try FileManager.default.copyItem(at: Self.fixtures.appendingPathComponent("fixed-oracle.sh"), to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let oracle = CommandOracle(Walkbook.Oracle(command: ["./oracle.sh", "fixed"]), walkbookDirectory: directory.url)

        let answers = oracle.answers(to: [Self.request("distance")])

        #expect(oracle.invocation?.0 == script.standardizedFileURL.path)
        #expect(answers == [.reply(values: ["midnight": 4.23, "rolling24h": 3.9], unit: "km", attribution: nil)])
    }

    /// Whether `pid` has gone — not merely been signalled — within `seconds`.
    private static func isGone(_ pid: pid_t, within seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if kill(pid, 0) == -1, errno == ESRCH {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return false
    }

    private static func request(_ figure: String) -> OracleRequest {
        OracleRequest(figure: figure, windows: ["midnight", "rolling24h"], capturedAt: Date(timeIntervalSince1970: 1_790_000_000), locale: "en_US", screen: "today", state: "light")
    }
}
