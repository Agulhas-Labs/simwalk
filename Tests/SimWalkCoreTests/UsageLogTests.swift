//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// The usage log is adoption ground truth (Brief §3), which only holds if it never costs the call it is recording — so the shape under test is "one JSON object per line, and silence when the log cannot be written".
struct UsageLogTests {
    @Test
    func eachCallAppendsOneJSONLine() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })

        log.record(tool: "validate", target: "example-walk.json", milliseconds: 4, succeeded: true)
        log.record(tool: "bundle inspect", target: "example.simwalk", milliseconds: 9, succeeded: true)

        let lines = try Self.lines(of: log)

        #expect(lines.count == 2)
        #expect(lines[0]["tool"] as? String == "validate")
        #expect(lines[0]["target"] as? String == "example-walk.json")
        #expect(lines[0]["ms"] as? Int == 4)
        #expect(lines[0]["ok"] as? Bool == true)
        #expect(lines[0]["ts"] as? String == "2026-08-16T08:00:00.000Z")
        #expect(lines[1]["tool"] as? String == "bundle inspect")
    }

    @Test
    func aFailedCallRecordsItsReasonAsOneBoundedLine() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 0) })

        log.record(tool: "validate", target: "torn.json", milliseconds: 1, succeeded: false, err: "line one\nline two\n" + String(repeating: "x", count: 500))

        let recorded = try #require(try Self.lines(of: log).first?["err"] as? String)

        #expect(recorded.count == 200)
        #expect(!recorded.contains("\n"))
        #expect(recorded.hasPrefix("line one line two "))
    }

    @Test
    func aLogThatCannotBeWrittenFailsSilentlyRatherThanReachingTheCaller() {
        let log = UsageLog(directory: URL(fileURLWithPath: "/dev/null/simwalk"), now: { Date(timeIntervalSince1970: 0) })

        log.record(tool: "validate", target: "anything", milliseconds: 1, succeeded: true)

        #expect(!FileManager.default.fileExists(atPath: log.fileURL.path))
    }

    @Test
    func concurrentWritersEachGetAWholeLine() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        let writers = 8
        let perWriter = 40

        DispatchQueue.concurrentPerform(iterations: writers) { writer in
            for call in 0 ..< perWriter {
                log.record(tool: "validate", target: "writer-\(writer)-call-\(call)", milliseconds: call, succeeded: true)
            }
        }

        let lines = try Self.lines(of: log)

        #expect(lines.count == writers * perWriter)
        #expect(Set(lines.compactMap { $0["target"] as? String }).count == writers * perWriter)
    }

    @Test
    func timestampsCarrySubSecondResolutionSoOrderingSurvives() throws {
        let directory = try TemporaryDirectory()
        let earlier = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200.001) })
        let later = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200.002) })

        earlier.record(tool: "validate", target: "first", milliseconds: 1, succeeded: true)
        later.record(tool: "validate", target: "second", milliseconds: 1, succeeded: true)

        let stamps = try Self.lines(of: earlier).map { $0["ts"] as? String }

        #expect(stamps.count == 2)
        #expect(stamps[0] != stamps[1])
    }

    /// Which session a call belongs to is what lets a status line price its own calls and nobody else's, so it has to survive the round trip and it has to be absent where nothing named one.
    @Test
    func asessionIsRecordedWhenOneIsNamedAndAbsentWhenNoneIs() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })

        log.record(tool: "walk", target: "example.json", milliseconds: 9, succeeded: true, session: "session-a")
        log.record(tool: "walk", target: "example.json", milliseconds: 9, succeeded: true)

        let lines = try Self.lines(of: log)
        let decoded = try Self.decoded(of: log)

        #expect(lines[0]["session"] as? String == "session-a")
        #expect(lines[1]["session"] == nil)
        #expect(decoded.map(\.session) == ["session-a", nil])
    }

    /// A failure's kind is what `simwalk usage` counts by, and it has to survive the round trip the same way `session` does: present when the call site named one, absent for a call that succeeded (where a kind means nothing) and for a failure whose site named none.
    @Test
    func akindIsRecordedWhenGivenAndAbsentOtherwise() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })

        log.record(tool: "walk", target: "nope.json", milliseconds: 1, succeeded: false, err: "cannot read walkbook", kind: .inputRefused)
        log.record(tool: "walk", target: "example.json", milliseconds: 9, succeeded: true)
        log.record(tool: "walk", target: "example.json", milliseconds: 9, succeeded: false, err: "unmapped site")

        let lines = try Self.lines(of: log)
        let decoded = try Self.decoded(of: log)

        #expect(lines[0]["kind"] as? String == "input-refused")
        #expect(lines[1]["kind"] == nil)
        #expect(lines[2]["kind"] == nil)
        #expect(decoded.map(\.kind) == [.inputRefused, nil, nil])
    }

    /// A round trip through every wire key at once — `decoded == original` on a fully-populated line — rather than one property checked at a time.
    ///
    /// `Entry.init(from:)` is hand-written, not synthesized: a `CodingKeys` case added without a matching line in that initializer still compiles clean, because an `Optional` property's implicit `nil` default already satisfies Swift's "every property initialized" rule, and the field would then silently decode as absent forever after. Comparing the whole struct rather than picking named fields is what makes this test the one that would fail the day a field is added and its decode line is not — this run pins it for every field that exists today.
    @Test
    func everyFieldSurvivesARoundTripAtOnce() throws {
        let original = UsageLog.Entry(
            timestamp: "2026-08-16T08:00:00.000Z",
            tool: "walk",
            target: "example.json",
            milliseconds: 9,
            succeeded: false,
            error: "the walk did not complete: crash",
            session: "session-a",
            screenshots: 3,
            imageTokens: 12210,
            treeBytes: 43890,
            answerBytes: 718,
            kind: .runnerFailed
        )

        let decoded = try JSONDecoder().decode(UsageLog.Entry.self, from: JSONEncoder().encode(original))

        #expect(decoded == original)
    }

    /// The log on a machine that has been running this tool since August is mostly lines written before the newest field existed, and a reader that refused them would report the tool as unused.
    @Test
    func alineWrittenBeforeTheNewestFieldsExistedStillDecodes() throws {
        let original = Data(#"{"ms":4,"ok":true,"target":"example.json","tool":"validate","ts":"2026-08-16T08:00:00.000Z"}"#.utf8)

        let entry = try JSONDecoder().decode(UsageLog.Entry.self, from: original)

        #expect(entry.tool == "validate")
        #expect(entry.session == nil)
        #expect(entry.tokensSaved == nil)
        #expect(entry.kind == nil)
        #expect(entry.succeeded)
    }

    /// Several binaries at different commits append to this file, so a `kind` value this build's `UsageFailureKind` has no case for — from one built after it — must not fail the whole line: the call's `tool`, `target` and (above all) `succeeded` still have to decode, or the failure itself disappears from every reader on the machine that has not been rebuilt yet.
    @Test
    func alineCarryingAKindThisBuildDoesNotKnowStillDecodesAndCountsAsAFailure() throws {
        let original = Data(#"{"ms":4,"ok":false,"err":"a walk that could not restore its device to a clean slate","target":"example.json","tool":"walk","ts":"2026-08-16T08:00:00.000Z","kind":"capture-corrupted"}"#.utf8)

        let entry = try JSONDecoder().decode(UsageLog.Entry.self, from: original)

        #expect(!entry.succeeded)
        #expect(entry.tool == "walk")
        #expect(entry.kind == nil)
        #expect(entry.unrecognizedKind == "capture-corrupted")
    }

    /// A line with no `kind` key at all, and one carrying a `kind` this build does not know, both decode to `kind == nil` — but only the second carries `unrecognizedKind`, which is what lets a reader tell "nothing was ever recorded" from "something was recorded that this build cannot place".
    @Test
    func anAbsentKindAndAnUnrecognizedKindAreDistinguishableAfterDecoding() throws {
        let noKindAtAll = try JSONDecoder().decode(UsageLog.Entry.self, from: Data(#"{"ms":1,"ok":false,"tool":"walk","ts":"2026-08-16T08:00:00.000Z"}"#.utf8))
        let unrecognizedKind = try JSONDecoder().decode(UsageLog.Entry.self, from: Data(#"{"ms":1,"ok":false,"tool":"walk","ts":"2026-08-16T08:00:00.000Z","kind":"capture-corrupted"}"#.utf8))

        #expect(noKindAtAll.kind == nil)
        #expect(noKindAtAll.unrecognizedKind == nil)
        #expect(unrecognizedKind.kind == nil)
        #expect(unrecognizedKind.unrecognizedKind == "capture-corrupted")
    }

    /// A `kind` present but not written as a string decodes the same way a string this build does not know does — as an unrecognised kind, not a torn line.
    ///
    /// `decodeIfPresent(String.self, forKey:)` throws on the wrong JSON type rather than returning `nil`, and a naive `try?` around it would have made this indistinguishable from a line that never carried the field at all.
    @Test
    func aNonStringKindDecodesAsUnrecognizedRatherThanTearingTheLine() throws {
        let entry = try JSONDecoder().decode(UsageLog.Entry.self, from: Data(#"{"ms":1,"ok":false,"tool":"walk","ts":"2026-08-16T08:00:00.000Z","kind":42}"#.utf8))

        #expect(entry.tool == "walk")
        #expect(!entry.succeeded)
        #expect(entry.kind == nil)
        #expect(entry.unrecognizedKind == "42")
    }

    /// `SIMWALK_USAGE_LOG` moves the log to the file it names — whatever that file is called — so a test or a review that drives the tool writes into a log it owns rather than the one `simwalk usage` reports adoption from.
    @Test
    func theOverrideVariableMovesTheStandardLogToTheFileItNames() throws {
        let directory = try TemporaryDirectory()
        let moved = directory.url.appendingPathComponent("scratch-calls.jsonl")

        let log = UsageLog.standard(environment: [UsageLog.overrideVariable: moved.path])

        // Checked before a single byte is written: a broken override recorded here would land in the
        // real `~/.simwalk/usage.jsonl` before the assertion below ever failed.
        #expect(UsageLog.overrideVariable == "SIMWALK_USAGE_LOG")
        try #require(log.fileURL == moved)
        #expect(log.directory.path == directory.url.path)

        log.record(tool: "validate", target: "book.json", milliseconds: 1, succeeded: true)

        #expect(try Self.decoded(of: log).map(\.tool) == ["validate"])
    }

    /// Unset, or set to nothing, the log is where it has always been: a variable emptied to switch it off must not name the working directory as a file.
    @Test
    func noOverrideOrABlankOneLeavesTheLogInHome() {
        let home = HomeDirectories.simwalk(environment: [:]).appendingPathComponent("usage.jsonl")

        #expect(UsageLog.standard(environment: [:]).fileURL == home)
        #expect(UsageLog.standard(environment: [UsageLog.overrideVariable: "  "]).fileURL == home)
    }

    private static func decoded(of log: UsageLog) throws -> [UsageLog.Entry] {
        let text = try String(contentsOf: log.fileURL, encoding: .utf8)
        return try text.split(separator: "\n").map { line in
            try JSONDecoder().decode(UsageLog.Entry.self, from: Data(line.utf8))
        }
    }

    private static func lines(of log: UsageLog, sourceLocation: SourceLocation = #_sourceLocation) throws -> [[String: Any]] {
        let text = try String(contentsOf: log.fileURL, encoding: .utf8)
        return try text.split(separator: "\n").map { line in
            let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
            return try #require(object as? [String: Any], sourceLocation: sourceLocation)
        }
    }
}
