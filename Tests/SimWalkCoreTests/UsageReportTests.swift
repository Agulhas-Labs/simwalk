//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// The reader over `~/.simwalk/usage.jsonl`, whose whole worth is that it does not overclaim: the log on a machine that has been running this tool since August is mostly lines that measured nothing, and a saving stated over them would be a ratio drawn over a population that was never weighed.
struct UsageReportTests {
    /// The line format shipped in August carried six keys and no measurement, and there are hundreds of them on this machine — a reader that refused them would report the tool as unused.
    @Test
    func alineWrittenBeforeTheMeasuredFieldsExistedStillDecodes() throws {
        let legacy = #"{"ms":2,"ok":true,"target":"example-walk.json","tool":"validate","ts":"2026-08-16T15:55:55Z"}"#

        let entry = try JSONDecoder().decode(UsageLog.Entry.self, from: Data(legacy.utf8))

        #expect(entry.tool == "validate")
        #expect(entry.milliseconds == 2)
        #expect(entry.succeeded)
        #expect(entry.screenshots == nil)
        #expect(entry.imageTokens == nil)
        #expect(entry.treeBytes == nil)
        #expect(entry.answerBytes == nil)
        #expect(entry.tokensSaved == nil)
    }

    /// A line that measured something reads back as the same measurement it was written with, and a report over it prices the call as its answer did.
    @Test
    func ameasuredLineRoundTripsThroughTheWireKeys() throws {
        let measured = #"{"imgTokens":12210,"ms":4,"ok":true,"outBytes":718,"shots":3,"target":"final.simwalk","tool":"bundle inspect","treeBytes":43890,"ts":"2026-09-05T19:33:20.248Z"}"#

        let entry = try JSONDecoder().decode(UsageLog.Entry.self, from: Data(measured.utf8))

        #expect(entry.screenshots == 3)
        #expect(entry.imageTokens == 12210)
        #expect(entry.treeBytes == 43890)
        #expect(entry.answerBytes == 718)
        #expect(entry.tokensSaved == ContextSaving(screenshotTokens: [12210], treeBytes: 43890, servedBytes: 718).savedTokens)
    }

    /// A tool that never ran has an honest answer, and it is not a refusal.
    @Test
    func alogThatDoesNotExistYetIsAnsweredRatherThanRefused() throws {
        let directory = try TemporaryDirectory()

        let answer = try UsageReport.render(fileURL: directory.url.appendingPathComponent("usage.jsonl"))

        #expect(answer.verdict == .unqualified("no calls recorded yet"))
        #expect(answer.verdict.exitCode == 0)
        #expect(answer.header.contains("calls: 0"))
    }

    /// A log that is *there* and will not open is a refusal, not a report of a machine that has never run the tool.
    ///
    /// `try?` around the read collapsed the two, and it ran the wrong way: the answer was "no calls recorded yet", exit 0, over a file holding six thousand of them. A directory standing where the file belongs is the cheap way to reproduce every cause at once.
    @Test
    func alogThatCannotBeReadRefusesRatherThanReportingNoCalls() throws {
        let directory = try TemporaryDirectory()
        let path = directory.url.appendingPathComponent("usage.jsonl")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)

        let thrown = try #require(#expect(throws: UsageLogReadError.self) {
            try UsageReport.render(fileURL: path)
        })

        #expect(thrown.description.hasPrefix(path.path + ": "))
        #expect(AnswerVerdict.refused(thrown.description).exitCode == AnswerVerdict.refusedExitCode)
    }

    /// The report's own shape: the log in the header, failures before the count of calls in the verdict, then latencies, then the saving and everything that keeps it from being read as a total.
    @Test
    func thereportLeadsWithFailuresAndStatesTheSavingAsAfloor() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "bundle inspect", target: "a.simwalk", milliseconds: 4, succeeded: true, saving: ContextSaving(screenshotTokens: [4070, 4070], treeBytes: 40000, servedBytes: 700))
        log.record(tool: "bundle inspect", target: "b.simwalk", milliseconds: 9, succeeded: false, err: "not a bundle")
        log.record(tool: "validate", target: "book.json", milliseconds: 1, succeeded: true)

        let text = try UsageReport.render(fileURL: log.fileURL).text

        #expect(text.hasPrefix("log: "))
        #expect(text.contains("calls: 3  days: 2026-08-16 → 2026-08-16"))
        // A failure the tool owns is something to flag, so the word in front of it is `qualified` — `ok` over a
        // failure read as a verdict the numbers did not support. (Pinned as `ok` before the verdict followed
        // the result.)
        #expect(text.contains("qualified — 1 failure across 3 calls"))
        #expect(text.contains("bundle inspect      2   p50 4ms   p90 9ms   1 failed"))
        #expect(text.contains("validate            1   p50 1ms   p90 1ms"))
        #expect(text.contains("measured savings — ~17k tokens saved (2 screenshots and 40 kB of accessibility trees at 4 bytes a token, against 700 B served): measured over 1 of 3 calls"))
        #expect(text.contains("1  bundle inspect call recorded no measurement — 1 of them failed and so stood in for nothing"))
        #expect(text.contains("1  validate call recorded no measurement anywhere in this window — no saving is claimed for them"))
        #expect(text.contains("~17k tokens saved is a floor, not a total: only the 1 call above was weighed."))
    }

    /// "Failed" means the same thing here as everywhere else `simwalk usage` uses it — it excludes `input-refused`.
    ///
    /// Folding a deliberate refusal into "failed" is the exact ambiguity `byTool` exists to avoid one section further down, and this section used to make it: a call this section names refused is now named as refused, not counted alongside a call that actually fell over.
    @Test
    func thesavingsSectionNamesFailedAndRefusedSeparately() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "bundle inspect", target: "a.simwalk", milliseconds: 4, succeeded: true, saving: ContextSaving(screenshotTokens: [4070], treeBytes: 40000, servedBytes: 700))
        log.record(tool: "bundle inspect", target: "b.simwalk", milliseconds: 1, succeeded: false, err: "the format is not what this build expects", kind: .runnerFailed)
        log.record(tool: "bundle inspect", target: "c.simwalk", milliseconds: 1, succeeded: false, err: "not a bundle", kind: .inputRefused)

        let text = try UsageReport.render(fileURL: log.fileURL).text

        #expect(text.contains("2  bundle inspect calls recorded no measurement — 1 of them failed and 1 was refused, so stood in for nothing"))
    }

    /// When every unmeasured call in the group was refused and none actually failed, the note names only that — not "0 of them failed".
    @Test
    func thesavingsSectionNamesOnlyRefusedWhenNothingActuallyFailed() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "bundle inspect", target: "a.simwalk", milliseconds: 4, succeeded: true, saving: ContextSaving(screenshotTokens: [4070], treeBytes: 40000, servedBytes: 700))
        log.record(tool: "bundle inspect", target: "b.simwalk", milliseconds: 1, succeeded: false, err: "not a bundle", kind: .inputRefused)

        let text = try UsageReport.render(fileURL: log.fileURL).text

        #expect(text.contains("1  bundle inspect call recorded no measurement — 1 of them was refused and so stood in for nothing"))
        #expect(!text.contains("0 of them failed"))
    }

    /// A caller deliberately testing a refusal path getting refused is the tool working, not the tool failing: the headline rate excludes `input-refused`, but says how many it left out rather than silently shrinking a number a reader may already have seen.
    @Test
    func theheadlineExcludesInputRefusedFailuresAndNamesTheCount() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "walk", target: "nope.json", milliseconds: 1, succeeded: false, err: "cannot read walkbook at nope.json", kind: .inputRefused)
        log.record(tool: "walk", target: "example.json", milliseconds: 1, succeeded: false, err: "the walk did not complete: crash", kind: .runnerFailed)
        log.record(tool: "walk", target: "example.json", milliseconds: 1, succeeded: true)

        let text = try UsageReport.render(fileURL: log.fileURL).text

        #expect(text.contains("qualified — 1 failure across 3 calls · 1 input refusal, not counted as failures"))
    }

    /// A failed `--parallel` walk writes a `walk` line and a `walk.parallel` one, and is one failed call: the second is the first's breakdown, not a call of its own.
    @Test
    func aParallelBreakdownLineIsNotCountedAsACallOrAFailure() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "walk", target: "example.json", milliseconds: 9, succeeded: false, err: "the walk did not complete: crash", kind: .runnerFailed)
        log.record(tool: UsageLog.parallelTool, target: "example.json", milliseconds: 8, succeeded: false, err: "the walk did not complete: crash", kind: .runnerFailed, parallel: ParallelTimings(shards: [], mergeMs: nil))

        let text = try UsageReport.render(fileURL: log.fileURL).text

        #expect(text.contains("1 failure across 1 call"))
        #expect(text.contains("calls: 1"))
        #expect(!text.contains(UsageLog.parallelTool))
    }

    /// No input refusals in the window: the note is left off rather than printed as "0 input refusals".
    @Test
    func theheadlineSaysNothingAboutInputRefusalsWhenThereAreNone() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "walk", target: "example.json", milliseconds: 1, succeeded: false, err: "the walk did not complete: crash", kind: .runnerFailed)

        let text = try UsageReport.render(fileURL: log.fileURL).text

        #expect(text.contains("1 failure across 1 call"))
        #expect(!text.contains("input refusal"))
    }

    /// Failures broken out by kind, most-used first, ties alphabetical — the same rule `byTool` follows.
    ///
    /// A line with no kind at all, and error text this build cannot place, reads as `unclassified` rather than being dropped or guessed at.
    @Test
    func thereportBreaksFailuresOutByKind() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "walk", target: "nope.json", milliseconds: 1, succeeded: false, err: "cannot read walkbook at nope.json", kind: .inputRefused)
        log.record(tool: "walk", target: "x.json", milliseconds: 1, succeeded: false, err: "bad settle", kind: .inputRefused)
        log.record(tool: "walk", target: "example.json", milliseconds: 1, succeeded: false, err: "the walk did not complete: crash", kind: .runnerFailed)
        log.record(tool: "walk", target: "old.json", milliseconds: 1, succeeded: false, err: "a mystery from before this field existed")
        log.record(tool: "walk", target: "example.json", milliseconds: 1, succeeded: true)

        let text = try UsageReport.render(fileURL: log.fileURL).text
        // Column width is the longest label present ("input-refused"/"runner-failed", both 13) — computed
        // rather than hand-counted, so this pins the arithmetic and not a guess at its result.
        let width = "input-refused".count

        #expect(text.contains("by failure kind:"))
        #expect(text.contains("  \("input-refused".rightPadded(width))  \("2".leftPadded(4))"))
        #expect(text.contains("  \("runner-failed".rightPadded(width))  \("1".leftPadded(4))"))
        #expect(text.contains("  \("unclassified".rightPadded(width))  \("1".leftPadded(4))"))
    }

    /// An unkinded old line is still placed correctly when its own error text is unambiguous — the report does not need every line rewritten to classify what the text already says plainly.
    ///
    /// Marked as inferred rather than shown identically to a line the field itself named: the two are different evidence for the same count, and a reader deciding how much to trust a `runner-failed` spike should be able to tell them apart.
    @Test
    func anUnkindedLineIsInferredFromItsOwnErrorText() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "walk", target: "nope.json", milliseconds: 1, succeeded: false, err: "cannot read walkbook at /nope.json: no such file")

        let text = try UsageReport.render(fileURL: log.fileURL).text

        #expect(text.contains("  \("input-refused".rightPadded("input-refused".count))  \("1".leftPadded(4))  (1 inferred from error text)"))
        #expect(!text.contains("unclassified"))
    }

    /// If the headline filtered on the stored `kind` field rather than on the same inferred classification the by-kind breakdown uses, this line — no stored kind, but unambiguous error text — would count as a failure instead of an excluded input refusal, and the headline would silently include what a caller engineered on purpose.
    ///
    /// This is the case a fresh-context review found no existing test would catch.
    @Test
    func theHeadlineExcludesAnInputRefusalInferredFromErrorTextWithNoStoredKind() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "walk", target: "nope.json", milliseconds: 1, succeeded: false, err: "cannot read walkbook at /nope.json: no such file")
        log.record(tool: "walk", target: "example.json", milliseconds: 1, succeeded: false, err: "the walk did not complete: crash")

        let text = try UsageReport.render(fileURL: log.fileURL).text

        #expect(text.contains("qualified — 1 failure across 2 calls · 1 input refusal, not counted as failures"))
    }

    /// The ruling's own example, scaled down: a tool row never says "N failed" when some of those are refusals a caller engineered on purpose — it says how many of each, so the two are never read as the same fact.
    @Test
    func byToolSeparatesFailedFromRefused() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "walk", target: "a.json", milliseconds: 1, succeeded: false, err: "bad settle", kind: .inputRefused)
        log.record(tool: "walk", target: "b.json", milliseconds: 1, succeeded: false, err: "bad settle", kind: .inputRefused)
        log.record(tool: "walk", target: "c.json", milliseconds: 1, succeeded: false, err: "the walk did not complete: crash", kind: .runnerFailed)
        log.record(tool: "walk", target: "d.json", milliseconds: 1, succeeded: true)

        let text = try UsageReport.render(fileURL: log.fileURL).text

        #expect(text.contains("1 failed · 2 refused"))
    }

    /// A tool with a real failure and no refusals at all keeps the plain "N failed" — the split only ever appears once there is something to split.
    @Test
    func byToolKeepsThePlainFailedCountWhenThereAreNoRefusals() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "walk", target: "c.json", milliseconds: 1, succeeded: false, err: "the walk did not complete: crash", kind: .runnerFailed)

        let text = try UsageReport.render(fileURL: log.fileURL).text

        #expect(text.contains("1 failed"))
        #expect(!text.contains("refused"))
    }

    /// The per-tool split reads the same classification the headline and the by-kind breakdown do — inferred kinds included — rather than the stored `kind` field alone.
    ///
    /// A line old enough to carry no `kind` but whose error text is unambiguous is still a refusal here, and a row that read only the stored field would count it as a plain failure instead — the same overclaim the ruling that split `byTool` in the first place exists to prevent, one field down.
    @Test
    func byToolsRefusedCountUsesTheInferredKindNotOnlyTheStoredOne() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "walk", target: "nope.json", milliseconds: 1, succeeded: false, err: "cannot read walkbook at /nope.json: no such file")

        let text = try UsageReport.render(fileURL: log.fileURL).text

        #expect(text.contains("p90 1ms   1 refused"))
        // A zero part is left off rather than printed: this row used to read `0 failed · 1 refused`.
        #expect(!text.contains("0 failed"))
    }

    /// A `kind` this build's `UsageFailureKind` has no case for is kept apart from a line that never carried one at all: the first is evidence of a binary ahead of this one, the second is a line older than the field.
    ///
    /// Both still count in the headline — an unrecognized kind is never assumed to be an `input-refused` it did not say it was.
    @Test
    func anUnrecognizedKindIsKeptApartFromUnclassifiedAndStillCounts() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "walk", target: "old.json", milliseconds: 1, succeeded: false, err: "a mystery from before this field existed")
        let handle = try FileHandle(forWritingTo: log.fileURL)
        try handle.seekToEnd()
        let rawLine = #"{"ts":"2026-08-16T08:00:00.000Z","tool":"walk","target":"new.json","ms":1,"ok":false,"err":"a device restore this build has never seen","kind":"capture-corrupted"}"# + "\n"
        try handle.write(contentsOf: Data(rawLine.utf8))
        try handle.close()

        let text = try UsageReport.render(fileURL: log.fileURL).text

        #expect(text.contains("2 failures across 2 calls"))
        #expect(!text.contains("input refusal"))
        #expect(text.contains("  \("unclassified".rightPadded("unrecognized-kind".count))  \("1".leftPadded(4))"))
        #expect(text.contains("  \("unrecognized-kind".rightPadded("unrecognized-kind".count))  \("1".leftPadded(4))"))
        #expect(text.contains("unclassified: no kind recorded, and the error text matched no rule this build knows"))
        #expect(text.contains("unrecognized-kind: recorded a kind this build's UsageFailureKind has no case for — from a newer simwalk binary (seen: capture-corrupted)"))
    }

    /// Several unrecognised kinds are not folded into one anonymous bucket: the explanation names every distinct raw value seen, so a reader deciding whether to upgrade knows what this build is behind, not just that it is.
    @Test
    func unrecognizedKindsAreNamedByTheirRawValuesNotFoldedAnonymously() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        try FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
        let lines = [
            #"{"ts":"2026-08-16T08:00:00.000Z","tool":"walk","target":"a.json","ms":1,"ok":false,"err":"boom","kind":"device-wiped"}"#,
            #"{"ts":"2026-08-16T08:00:01.000Z","tool":"walk","target":"b.json","ms":1,"ok":false,"err":"boom","kind":"capture-corrupted"}"#,
            #"{"ts":"2026-08-16T08:00:02.000Z","tool":"walk","target":"c.json","ms":1,"ok":false,"err":"boom","kind":"device-wiped"}"#,
        ]
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: log.fileURL)

        let text = try UsageReport.render(fileURL: log.fileURL).text

        #expect(text.contains("unrecognized-kind: recorded a kind this build's UsageFailureKind has no case for — from a newer simwalk binary (seen: capture-corrupted, device-wiped)"))
    }

    /// The failure mode the previous test's docstring claims but does not actually exercise: its error text matches no inference rule, so it passes whether or not inference is allowed to override an unrecognized kind.
    ///
    /// This one's error text is the marker `WalkbookLoadError.unreadable` writes — unambiguous, and squarely `.inputRefused` when inferred on a line with no stored kind at all. Stored *alongside* a kind this build does not recognise, it must stay `unrecognized-kind`: inference exists for a line that said nothing, not for overriding one that said something this build cannot place.
    @Test
    func anUnrecognizedKindIsNeverOverriddenByInferenceFromItsOwnErrorText() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        try FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
        let rawLine = #"{"ts":"2026-08-16T08:00:00.000Z","tool":"walk","target":"new.json","ms":1,"ok":false,"err":"cannot read walkbook at /nope.json: no such file","kind":"device-wiped"}"# + "\n"
        try Data(rawLine.utf8).write(to: log.fileURL)

        let text = try UsageReport.render(fileURL: log.fileURL).text

        #expect(text.contains("1 failure across 1 call"))
        #expect(!text.contains("input refusal"))
        #expect(!text.contains("input-refused"))
        #expect(text.contains("  \("unrecognized-kind".rightPadded("unrecognized-kind".count))  \("1".leftPadded(4))"))
    }

    /// Nothing failed: no heading is printed over an empty breakdown, on the same rule that keeps a clean walk from printing "0 screens unreachable".
    @Test
    func noFailureKindSectionWhenNothingFailed() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "validate", target: "book.json", milliseconds: 1, succeeded: true)

        let text = try UsageReport.render(fileURL: log.fileURL).text

        #expect(!text.contains("by failure kind"))
    }

    /// A log in which nothing weighed anything says exactly that, rather than reporting a saving of zero over a population that measured nothing.
    @Test
    func alogWithNoMeasurementSaysNothingWasWeighed() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "validate", target: "book.json", milliseconds: 1, succeeded: true)

        let text = try UsageReport.render(fileURL: log.fileURL).text

        #expect(text.contains("measured savings — nothing weighed: no call in this log recorded what it stood in for"))
        #expect(!text.contains("floor"))
    }

    /// A torn line — an interrupted write, or a version of the tool this build does not understand — is counted and declared rather than costing the rest of the file or passing unmentioned.
    @Test
    func atornLineIsDeclaredRatherThanSwallowed() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "validate", target: "book.json", milliseconds: 1, succeeded: true)
        let handle = try FileHandle(forWritingTo: log.fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"ms":1,"#.utf8))
        try handle.close()

        let answer = try UsageReport.render(fileURL: log.fileURL)

        #expect(answer.text.contains("calls: 1"))
        #expect(answer.text.contains("1 malformed line skipped — this report is short by whatever they recorded"))
        // The count was printed and the verdict said `ok` over it, which is a report stating its own
        // shortfall and then exiting as though it had none.
        #expect(answer.verdict == .qualified(["1 malformed line skipped"], detail: "0 failures across 1 call"))
        #expect(answer.verdict.exitCode == AnswerVerdict.qualifiedExitCode)
    }

    /// A file holding nothing but torn lines is qualified too, rather than an unblemished "no calls recorded yet".
    @Test
    func alogOfNothingButTornLinesIsQualifiedRatherThanEmpty() throws {
        let directory = try TemporaryDirectory()
        let path = directory.url.appendingPathComponent("usage.jsonl")
        try Data("{\"ms\":1,\nnot json at all\n".utf8).write(to: path)

        let answer = try UsageReport.render(fileURL: path)

        #expect(answer.verdict == .qualified(["2 malformed lines skipped"], detail: "no calls recorded yet"))
        #expect(answer.verdict.exitCode == AnswerVerdict.qualifiedExitCode)
    }

    // MARK: - What the third review found

    /// ArgumentParser's own sentences, as MCP servers wrote them for a walkbook named `-x.json` or `--version` and for a negative `settle` passed as its own token — this server's own bugs, every one.
    ///
    /// They stay `unclassified` and count in the headline: reading them as `input-refused` put three real failures where the headline could not see them.
    @Test
    func argumentParsersOwnSentencesCountAsFailuresNotRefusals() throws {
        let directory = try TemporaryDirectory()
        let lines = [
            #"{"err":"Missing expected argument '<walkbook>'","ms":0,"ok":false,"session":"s","target":"-x.json","tool":"validate","ts":"2026-09-06T09:35:53.070Z"}"#,
            #"{"err":"Missing expected argument '<walkbook>'","ms":0,"ok":false,"session":"s","target":"--version","tool":"validate","ts":"2026-09-06T09:35:53.070Z"}"#,
            #"{"err":"Missing value for '--settle <settle>'","ms":2,"ok":false,"session":"s","target":"/tmp/nope.json","tool":"walk","ts":"2026-09-06T09:40:58.093Z"}"#,
        ]
        let path = directory.url.appendingPathComponent("usage.jsonl")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: path)

        let text = try UsageReport.render(fileURL: path).text

        #expect(text.contains("qualified — 3 failures across 3 calls"))
        #expect(!text.contains("input refusal"))
        #expect(text.contains("  \("unclassified".rightPadded("unclassified".count))  \("3".leftPadded(4))"))
    }

    /// A count read off the stored field is not marked as inferred: the note is evidence of a different kind, and printing it on every stored count would make it mean nothing.
    ///
    /// Whole-line equality, because a check on the prefix passes whatever follows it.
    @Test
    func astoredKindIsNeverMarkedAsInferred() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "walk", target: "a.json", milliseconds: 1, succeeded: false, err: "the walk did not complete: crash", kind: .runnerFailed)
        log.record(tool: "walk", target: "b.json", milliseconds: 1, succeeded: false, err: "the walk did not complete: crash")

        let lines = try UsageReport.render(fileURL: log.fileURL).text.split(separator: "\n").map(String.init)

        #expect(lines.contains("  runner-failed     2  (1 inferred from error text)"))
        #expect(!lines.contains { $0.contains("(2 inferred") })
    }

    /// The savings note's "refused" reads the same classification as everything else that prints the word — a line older than the field is a refusal there too when its own text says so.
    @Test
    func thesavingsNoteCountsARefusalInferredFromErrorText() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "bundle inspect", target: "a.simwalk", milliseconds: 4, succeeded: true, saving: ContextSaving(screenshotTokens: [4070], treeBytes: 40000, servedBytes: 700))
        log.record(tool: "bundle inspect", target: "b.simwalk", milliseconds: 1, succeeded: false, err: "/tmp is not named as a capture bundle — a bundle directory ends in .simwalk")

        let text = try UsageReport.render(fileURL: log.fileURL).text

        #expect(text.contains("1  bundle inspect call recorded no measurement — 1 of them was refused and so stood in for nothing"))
    }

    /// "Refused" and "failed" are one pair of predicates, and a call that succeeded is neither — whatever a line claims beside it.
    @Test
    func asucceededCallIsNeitherAFailureNorARefusalAndHasNoKind() {
        let succeeded = UsageLog.Entry(timestamp: "2026-08-16T08:00:00.000Z", tool: "walk", target: nil, milliseconds: 1, succeeded: true, error: nil, kind: .inputRefused)
        let refused = UsageLog.Entry(timestamp: "2026-08-16T08:00:00.000Z", tool: "walk", target: nil, milliseconds: 1, succeeded: false, error: "x", kind: .inputRefused)
        let failed = UsageLog.Entry(timestamp: "2026-08-16T08:00:00.000Z", tool: "walk", target: nil, milliseconds: 1, succeeded: false, error: "x")

        #expect(succeeded.classifiedFailureKind == nil)
        #expect(!succeeded.isRefusal)
        #expect(!succeeded.isFailure)
        #expect(refused.isRefusal)
        #expect(!refused.isFailure)
        #expect(failed.isFailure)
        #expect(!failed.isRefusal)
    }

    // MARK: - The verdict follows the result (#25)

    /// `ok` only over nothing to flag — and refusals alone are nothing to flag.
    ///
    /// They are the tool working, so a log of nothing else still reads `ok`, says what it left out, and exits 0.
    @Test
    func alogOfNothingButRefusalsIsOk() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "walk", target: "a.json", milliseconds: 1, succeeded: false, err: "no such file", kind: .inputRefused)
        log.record(tool: "walk", target: "b.json", milliseconds: 1, succeeded: true)

        let answer = try UsageReport.render(fileURL: log.fileURL)

        #expect(answer.verdict == .unqualified("0 failures across 2 calls · 1 input refusal, not counted as failures"))
        #expect(answer.verdict.exitCode == 0)
    }

    /// A failure the tool owns is something to flag: the verdict is `qualified`, names it, and exits 2 — the contract's wording for an answer with a qualification, where `ok —` in front of it read as a verdict the numbers did not support.
    @Test
    func afailureMakesTheVerdictQualified() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "walk", target: "a.json", milliseconds: 1, succeeded: false, err: "the walk did not complete: crash", kind: .runnerFailed)
        log.record(tool: "walk", target: "b.json", milliseconds: 1, succeeded: false, err: "no such file", kind: .inputRefused)

        let answer = try UsageReport.render(fileURL: log.fileURL)

        #expect(answer.verdict == .qualified(["1 failure across 2 calls"], detail: "1 input refusal, not counted as failures"))
        #expect(answer.verdict.exitCode == AnswerVerdict.qualifiedExitCode)
    }

    // MARK: - Failures named by reason (#25)

    /// Within each kind, the reasons its calls recorded, most-recorded first — so a reader can tell which failure is still costing walks.
    @Test
    func failuresAreGroupedByReasonWithinTheirKind() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "walk", target: "a.json", milliseconds: 1, succeeded: false, err: "the walk did not complete: snapshot", kind: .runnerFailed)
        log.record(tool: "walk", target: "b.json", milliseconds: 1, succeeded: false, err: "the walk did not complete: crash", kind: .runnerFailed)
        log.record(tool: "walk", target: "c.json", milliseconds: 1, succeeded: false, err: "the walk did not complete: crash", kind: .runnerFailed)
        log.record(tool: "walk", target: "d.json", milliseconds: 1, succeeded: false, err: "no such file", kind: .inputRefused)
        log.record(tool: "walk", target: "e.json", milliseconds: 1, succeeded: false, kind: .toolError)

        let lines = try UsageReport.render(fileURL: log.fileURL).text.split(separator: "\n").map(String.init)
        let section = try #require(lines.firstIndex(of: "by failure kind:"))

        #expect(Array(lines.dropFirst(section + 1).prefix(7)) == [
            "  runner-failed     3",
            "         2  the walk did not complete: crash",
            "         1  the walk did not complete: snapshot",
            "  input-refused     1",
            "         1  no such file",
            "  tool-error        1",
            "         1  (no reason recorded)",
        ])
    }

    /// Under redaction every reason is a token, the same reason is the same token wherever it appears, the text itself is nowhere in the report — and the rows line up with the unredacted report's, because both are ordered by the real text.
    @Test
    func aredactedReportCarriesTokensInTheUnredactedReportsOrder() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "walk", target: "a.json", milliseconds: 1, succeeded: false, err: "cannot write /Users/someone/secret.simwalk", kind: .runnerFailed)
        log.record(tool: "validate", target: "b.json", milliseconds: 1, succeeded: false, err: "cannot write /Users/someone/secret.simwalk", kind: .toolError)
        log.record(tool: "walk", target: "c.json", milliseconds: 1, succeeded: false, err: "a second reason", kind: .runnerFailed)
        let redactor = Redactor(salt: Data("fixed".utf8))

        let redacted = try UsageReport.render(fileURL: log.fileURL, redactor: redactor).text
        let plain = try UsageReport.render(fileURL: log.fileURL).text
        let token = redactor.reason("cannot write /Users/someone/secret.simwalk")

        #expect(!redacted.contains("secret"))
        #expect(!redacted.contains("a second reason"))
        #expect(redacted.components(separatedBy: token).count == 3)
        #expect(redacted.contains("reasons are pseudonymised"))
        #expect(!plain.contains("reasons are pseudonymised"))
        #expect(redacted.replacingOccurrences(of: token, with: "cannot write /Users/someone/secret.simwalk")
            .replacingOccurrences(of: redactor.reason("a second reason"), with: "a second reason")
            .components(separatedBy: "\n").filter { !$0.contains("reasons are pseudonymised") } == plain.components(separatedBy: "\n"))
    }

    /// Most reasons quote the path they were pointed at, so one kind lists a handful and counts the rest rather than letting a bad week swamp the report.
    @Test
    func akindListsItsTopReasonsAndCountsTheRest() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        for index in 1 ... 7 {
            log.record(tool: "walk", target: "\(index).json", milliseconds: 1, succeeded: false, err: "cannot read walkbook at /\(index).json", kind: .inputRefused)
        }

        let text = try UsageReport.render(fileURL: log.fileURL).text

        #expect(text.contains("         1  cannot read walkbook at /5.json"))
        #expect(!text.contains("cannot read walkbook at /6.json"))
        #expect(text.contains("      … and 2 more distinct reasons"))
    }

    // MARK: - A window (#25)

    /// `--since` narrows every section to the calls made since its start, and the header names the window and how many calls the whole log holds, so a count is never read without it.
    @Test
    func awindowNarrowsTheReportAndTheHeaderNamesIt() throws {
        let directory = try TemporaryDirectory()
        let now = Date(timeIntervalSince1970: 1_786_867_200)
        let path = directory.url.appendingPathComponent("usage.jsonl")
        for (daysAgo, failed) in [(10.0, true), (4.0, true), (2.0, false), (0.5, true)] {
            UsageLog(fileURL: path, now: { now.addingTimeInterval(-daysAgo * 86400) })
                .record(tool: "walk", target: "a.json", milliseconds: 1, succeeded: !failed, err: failed ? "the walk did not complete: crash" : nil, kind: failed ? .runnerFailed : nil)
        }
        let window = try #require(UsageWindow(spelling: "3d", now: now))

        let answer = try UsageReport.render(fileURL: path, window: window)

        // Round 5: the window's start prints to the second, not the millisecond `ts` lines carry.
        #expect(answer.header == "log: \(path.path.tildedPath)  window: 3d from 2026-08-13T08:00:00Z  calls: 2 of 4  days: 2026-08-14 → 2026-08-15")
        #expect(answer.verdict == .qualified(["1 failure across 2 calls"], detail: ""))
    }

    /// A window with nothing in it is an honest answer, and says the log is not empty.
    @Test
    func awindowWithNoCallsSaysSoRatherThanNoCallsEver() throws {
        let directory = try TemporaryDirectory()
        let now = Date(timeIntervalSince1970: 1_786_867_200)
        let log = UsageLog(directory: directory.url, now: { now.addingTimeInterval(-30 * 86400) })
        log.record(tool: "validate", target: "book.json", milliseconds: 1, succeeded: true)

        let answer = try UsageReport.render(fileURL: log.fileURL, window: UsageWindow(spelling: "12h", now: now))

        #expect(answer.header.hasSuffix("calls: 0 of 1"))
        #expect(answer.verdict == .unqualified("no calls in this window"))
    }
}

// MARK: - Redaction round 5

extension UsageReportTests {
    /// `redactor` is an autoclosure: building it is only ever forced if a reason is actually about to be printed redacted, so a log with no failures at all must not touch whatever the expression would have done (here, incrementing a counter standing in for `Redactor.standard`'s file write).
    @Test
    func theRedactorIsNeverBuiltOverALogWithNoFailures() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "validate", target: "book.json", milliseconds: 1, succeeded: true)
        var built = 0

        _ = try UsageReport.render(fileURL: log.fileURL, redactor: {
            built += 1
            return Redactor(salt: Data("salt".utf8))
        }())

        #expect(built == 0)
    }

    /// Nor when the only failure recorded no reason at all — there is nothing there for a token to stand in for.
    @Test
    func theRedactorIsNeverBuiltWhenTheOnlyFailureHasNoReason() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "walk", target: "a.json", milliseconds: 1, succeeded: false, kind: .runnerFailed)
        var built = 0

        _ = try UsageReport.render(fileURL: log.fileURL, redactor: {
            built += 1
            return Redactor(salt: Data("salt".utf8))
        }())

        #expect(built == 0)
    }

    /// The same expression *is* forced once a failure with a real reason is present — the autoclosure defers, it does not disable.
    @Test
    func theRedactorIsBuiltExactlyOnceWhenThereIsSomethingToRedact() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "walk", target: "a.json", milliseconds: 1, succeeded: false, err: "the walk did not complete: crash", kind: .runnerFailed)
        var built = 0

        _ = try UsageReport.render(fileURL: log.fileURL, redactor: {
            built += 1
            return Redactor(salt: Data("salt".utf8))
        }())

        #expect(built == 1)
    }

    /// A log path outside home is shown in full unless `redacting` says otherwise — the default matches every call site that predates this parameter.
    @Test
    func theHeaderPathIsShownInFullUnlessRedactingIsRequested() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "validate", target: "book.json", milliseconds: 1, succeeded: true)

        let plain = try UsageReport.render(fileURL: log.fileURL)

        #expect(plain.header.hasPrefix("log: \(log.fileURL.path)"))
    }

    /// `redacting: true` over a path outside home replaces it with a bare basename and says why — an absolute path there routinely encodes a username or a review's own directory layout, which a report meant to be pasted must not carry regardless of whether any reason needed a token.
    @Test
    func redactingReplacesAnOutsideHomePathWithItsBasename() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "validate", target: "book.json", milliseconds: 1, succeeded: true)

        let answer = try UsageReport.render(fileURL: log.fileURL, redacting: true)

        #expect(answer.header.hasPrefix("log: \(log.fileURL.lastPathComponent)  (path redacted — outside home)"))
        #expect(!answer.header.contains(directory.url.path))
    }
}
