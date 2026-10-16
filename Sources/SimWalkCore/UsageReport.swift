//
// Copyright © Agulhas Labs
//

import Foundation

/// Renders `~/.simwalk/usage.jsonl` as the adoption review it exists to feed (Brief §3): what was called, how long it took, what failed, and what the answers stood in for.
///
/// **The saving is stated as a floor and never as a total.** Only an answer over a capture bundle weighs anything — a validation stands in for no screenshot and no tree — and the lines this file has held since August carry no measurement at all, so a ratio over "every call" would be a ratio over a population most of which was never weighed. Three numbers are kept apart and each says what it is: what was measured, what a measuring tool recorded nothing for, and what has no denominator to record.
public struct UsageReport {
    /// The report for the log at `fileURL`.
    ///
    /// A log that is not there yet is not a refusal: a tool nobody has run has an honest answer, and it is that no call has been recorded. A log that *is* there and cannot be read is a refusal — see ``UsageLogReadError``, and note that the two used to be one answer running the wrong way.
    ///
    /// **The verdict word agrees with what the report found.** `ok` only when there is nothing to flag; a failure the tool owns, or a line this build could not decode, makes the report `qualified` and names it. `ok —` in front of ninety-nine failures read as a verdict the numbers did not support, and a report that states its own shortfall and then exits as though it had none is the shape this contract exists to refuse.
    ///
    /// `window` narrows the report to calls made since its start, and the header names it beside how many calls the whole log holds — a count read without its window is the misreading a window invites. `redactor` pseudonymises failure reasons; `nil` prints them as recorded, and the command line passes one unless it was asked for `--unredact`.
    ///
    /// **`redactor` is an autoclosure and is never forced unless a reason is actually about to be printed redacted.** A caller building it inline as `Redactor.standard(saltFile:)` — the command line's own call — must not create that file merely by calling this over a log with no failures, or with failures that carry no reason at all.
    ///
    /// `redacting` gates the header's log path independently of whether a `Redactor` ever gets built: an absolute path outside home routinely encodes a username or a review's own directory layout, and a log with nothing to redact must still not print it under `--unredact`'s default.
    public static func render(fileURL: URL, window: UsageWindow? = nil, redacting: Bool = false, redactor makeRedactor: @autoclosure () -> Redactor? = nil) throws -> Answer {
        let read = try entries(at: fileURL)
        let calls = window.map { window in read.entries.filter { window.contains($0) } } ?? read.entries
        var header = "log: \(Self.reportedLogPath(fileURL, redacting: redacting))"
        // To the second, not the millisecond `Timestamp.string` carries: `window.start` is already floored
        // to that precision, so what a reader sees here is exactly what `contains` compared against, and
        // the report does not reveal the instant it ran down to a fraction nobody asked for.
        if let window {
            header += "  window: \(window.spelling) from \(Timestamp.wholeSecondString(from: window.start))"
        }
        header += "  calls: \(calls.count)" + (window == nil ? "" : " of \(read.entries.count)")
        let skipped = [AnswerVerdict.qualification(read.malformed, "malformed line", "skipped")].compactMap(\.self)
        guard !calls.isEmpty else {
            return Answer(
                header: header,
                verdict: .reporting(qualifications: skipped, detail: read.entries.isEmpty ? "no calls recorded yet" : "no calls in this window"),
                residue: malformedLines(read.malformed)
            )
        }
        let days = calls.map(\.day).sorted()
        return Answer(
            // The span the report is *over*, which is its subject rather than its provenance: a reader
            // asking "is this the fortnight I mean" has no other way to tell, and it is not the date the
            // answer was produced on. Nothing here names the day this ran or the machine it ran on.
            header: "\(header)  days: \(days.first ?? "?") → \(days.last ?? "?")",
            verdict: verdict(over: calls, skipped: skipped),
            residue: malformedLines(read.malformed) + byTool(calls) + byFailureKind(calls, redactor: makeRedactor) + savings(calls)
        )
    }

    /// The log path as the header states it: `~`-relative under home, unchanged either way, and a bare basename under redaction when it sits outside home — where `tildedPath` leaves it fully absolute.
    private static func reportedLogPath(_ fileURL: URL, redacting: Bool) -> String {
        let tilded = fileURL.path.tildedPath
        guard redacting, tilded == fileURL.path else { return tilded }
        return "\(fileURL.lastPathComponent)  (path redacted — outside home)"
    }

    /// The headline: the failures the tool owns before the calls they were among, and the refusals it left out, named rather than silently subtracted.
    ///
    /// A caller deliberately testing a refusal path getting refused is the tool working, not the tool failing, so ``UsageLog/Entry/isRefusal`` is not counted — but a reader may already have seen the larger number, so the verdict says how many it left out. The two halves are built apart and joined here, so the word in front of them is decided by the failures alone: `qualified` when there are any, and `ok` only over none.
    private static func verdict(over entries: [UsageLog.Entry], skipped: [String]) -> AnswerVerdict {
        let failures = entries.filter(\.isFailure).count
        let refusals = entries.filter(\.isRefusal).count
        let tally = "\(failures) failure\(failures == 1 ? "" : "s") across \(entries.count) call\(entries.count == 1 ? "" : "s")"
        let excluded = refusals > 0 ? "\(refusals) input refusal\(refusals == 1 ? "" : "s"), not counted as failures" : nil
        guard failures > 0 else {
            return .reporting(qualifications: skipped, detail: ([tally] + [excluded].compactMap(\.self)).joined(separator: " · "))
        }
        return .reporting(qualifications: [tally] + skipped, detail: excluded ?? "")
    }

    /// One line per tool, most-used first, with the two latencies a reader acts on and the failures before them.
    ///
    /// Failed and refused are counted separately rather than folded into one "failed": a caller deliberately testing a refusal path getting refused is not the same fact as the tool falling over, and a row reading "60 failed" would be the exact complaint that started this taxonomy, one level down. Either part is left off at zero, on the rule that keeps a clean walk from printing `0 screens unreachable`.
    private static func byTool(_ entries: [UsageLog.Entry]) -> [String] {
        let width = entries.map(\.tool.count).max() ?? 0
        return ["", "by tool:"] + grouped(entries, by: \.tool).map { tool, group in
            let sorted = group.map(\.milliseconds).sorted()
            let failed = group.filter(\.isFailure).count
            let refused = group.filter(\.isRefusal).count
            let outcomes = [failed > 0 ? "\(failed) failed" : nil, refused > 0 ? "\(refused) refused" : nil].compactMap(\.self)
            let line = "  \(tool.rightPadded(width))  \(String(group.count).leftPadded(5))   p50 \(percentile(sorted, 50))ms   p90 \(percentile(sorted, 90))ms"
            return outcomes.isEmpty ? line : line + "   " + outcomes.joined(separator: " · ")
        }
    }

    /// Failures broken out by kind, and each kind by the reasons its calls recorded — so a reader can act on a `runner-failed` or a `route-unreachable` without reading past every `input-refused` a caller engineered on purpose, and can tell whether a known bug is still costing walks.
    ///
    /// Absent when nothing failed — a heading printed over nothing is the one this contract refuses elsewhere too. A count reached by inference rather than a stored field says so, and `unclassified` is explained rather than left for a reader to guess at — and kept apart from `unrecognized-kind`, which is a different gap: a kind this build's own `UsageFailureKind` has no case for, from a binary ahead of it, rather than a line with nothing to go on at all.
    private static func byFailureKind(_ entries: [UsageLog.Entry], redactor makeRedactor: () -> Redactor?) -> [String] {
        let failed = entries.filter { !$0.succeeded }
        guard !failed.isEmpty else { return [] }
        let groups = grouped(failed, by: \.failureKindLabel)
        let width = groups.map(\.0.count).max() ?? 0
        // Resolved once, and only when a failure actually carries a reason to redact: `makeRedactor` is
        // what touches disk (`Redactor.standard` creates the salt file on first use), and a log with no
        // failures reaching this line, or failures that all recorded no reason, must not create it.
        let redactor = failed.contains { !($0.error ?? "").isEmpty } ? makeRedactor() : nil
        var lines = ["", "by failure kind:"]
        for (label, group) in groups {
            let inferred = group.filter(\.failureKindWasInferred).count
            let note = inferred > 0 ? "  (\(inferred) inferred from error text)" : ""
            lines.append("  \(label.rightPadded(width))  \(String(group.count).leftPadded(4))\(note)")
            lines += reasons(group, redactor: redactor)
        }
        if groups.contains(where: { $0.0 == Self.unclassifiedLabel }) {
            lines.append("    \(Self.unclassifiedLabel): no kind recorded, and the error text matched no rule this build knows")
        }
        // Named rather than left as one opaque bucket: several unrecognised kinds folding into one count
        // says only that this build is behind, never behind *what* — the raw values are the one thing a
        // reader deciding whether to upgrade actually wants out of this line.
        if let unrecognized = groups.first(where: { $0.0 == Self.unrecognizedKindLabel })?.1 {
            let raw = Set(unrecognized.compactMap(\.unrecognizedKind)).sorted().joined(separator: ", ")
            lines.append("    \(Self.unrecognizedKindLabel): recorded a kind this build's UsageFailureKind has no case for — from a newer simwalk binary (seen: \(raw))")
        }
        if redactor != nil {
            lines.append("    reasons are pseudonymised — one token per reason, the same from one report to the next on this machine; --unredact prints them")
        }
        return lines
    }

    /// The reasons one kind's calls recorded, most-recorded first — the rows that say which failure is still happening.
    ///
    /// Ordered by the real text even when redacted, so a redacted report and its `--unredact` twin line up row for row. Capped, because most reasons quote the path the call was pointed at and a bad week would otherwise swamp the report; the log still holds every one, and the cap says how many it left out.
    private static func reasons(_ group: [UsageLog.Entry], redactor: Redactor?) -> [String] {
        let byReason = grouped(group) { $0.error ?? "" }
        var lines = byReason.prefix(reasonLimit).map { reason, calls in
            // A line with no reason carries no name, so it reads the same redacted or not.
            let shown = reason.isEmpty ? "(no reason recorded)" : redactor?.reason(reason) ?? reason
            return "      \(String(calls.count).leftPadded(4))  \(shown)"
        }
        let unlisted = byReason.count - reasonLimit
        if unlisted > 0 {
            lines.append("      … and \(unlisted) more distinct reason\(unlisted == 1 ? "" : "s")")
        }
        return lines
    }

    /// How many reasons one kind lists before it counts the rest.
    private static var reasonLimit: Int {
        5
    }

    /// A line with no stored kind whose error text matched no rule — genuinely nothing to go on, old or new.
    ///
    /// `fileprivate` so ``UsageLog/Entry/failureKindLabel`` (below, in this file) groups under the identical string rather than a second literal that could drift from this one.
    fileprivate static var unclassifiedLabel: String {
        "unclassified"
    }

    /// A line whose stored `kind` this build's `UsageFailureKind` has no case for — necessarily from a binary at a commit ahead of this one (Codable decodes it leniently rather than losing the line).
    fileprivate static var unrecognizedKindLabel: String {
        "unrecognized-kind"
    }

    /// What the measured calls saved, and everything that keeps that figure from being read as a total.
    private static func savings(_ entries: [UsageLog.Entry]) -> [String] {
        let measured = entries.filter { $0.tokensSaved != nil }
        guard !measured.isEmpty else {
            return ["", "measured savings — nothing weighed: no call in this log recorded what it stood in for"]
        }
        let measuring = Set(measured.map(\.tool))
        let saved = measured.reduce(0) { $0 + ($1.tokensSaved ?? 0) }
        let screenshots = measured.reduce(0) { $0 + ($1.screenshots ?? 0) }
        let trees = measured.reduce(0) { $0 + ($1.treeBytes ?? 0) }
        let served = measured.reduce(0) { $0 + ($1.answerBytes ?? 0) }
        let headline = "\(TokenEstimate.short(saved)) saved"
        var lines = [
            "",
            "measured savings — \(headline) (\(screenshots) screenshot\(screenshots == 1 ? "" : "s") and \(TokenEstimate.basis(bytes: trees, of: "accessibility trees")), "
                + "against \(ByteSize.short(served)) served): measured over \(measured.count) of \(entries.count) call\(entries.count == 1 ? "" : "s")",
        ]
        // The calls a measuring tool made that recorded nothing. Named rather than left to shrink the
        // denominator in silence: a ratio "measured over 53 of 137" says how many measured, never how many
        // could have and did not, and only one of those is a fact about the tool.
        let unrecorded = entries.filter { measuring.contains($0.tool) && $0.tokensSaved == nil }
        if !unrecorded.isEmpty {
            lines.append(
                "  \(String(unrecorded.count).leftPadded(4))  \(named(unrecorded)) call\(unrecorded.count == 1 ? "" : "s") recorded no measurement"
                    + Self.failedAndRefusedNote(among: unrecorded)
            )
        }
        // The calls no denominator exists for anywhere in the window. Derived from which tools measured
        // anything rather than from a list of names, so a tool that starts measuring leaves this set by
        // itself — and stated as a fact about *this window* rather than about the tools, because a verb
        // that weighs its answers looks exactly like one that cannot until the day it is next run.
        let unpriced = entries.filter { !measuring.contains($0.tool) }
        if !unpriced.isEmpty {
            lines.append("  \(String(unpriced.count).leftPadded(4))  \(named(unpriced)) call\(unpriced.count == 1 ? "" : "s") recorded no measurement anywhere in this window — no saving is claimed for them")
        }
        if !unrecorded.isEmpty || !unpriced.isEmpty {
            lines.append("        \(headline) is a floor, not a total: only the \(measured.count) call\(measured.count == 1 ? " above was" : "s above were") weighed.")
        }
        return lines
    }

    /// The reason a set of unmeasured calls stood in for nothing, in the one wording `simwalk usage` gives "failed" everywhere else: it excludes `input-refused`, and a refusal is named as one rather than folded into the same word.
    ///
    /// Calling every call that did not succeed "failed" here would be the ambiguity `byTool` exists to avoid, one section further down.
    private static func failedAndRefusedNote(among entries: [UsageLog.Entry]) -> String {
        let failed = entries.filter(\.isFailure).count
        let refused = entries.filter(\.isRefusal).count
        return switch (failed > 0, refused > 0) {
        case (true, true):
            " — \(failed) of them failed and \(refused) \(refused == 1 ? "was" : "were") refused, so stood in for nothing"
        case (true, false):
            " — \(failed) of them failed and so stood in for nothing"
        case (false, true):
            " — \(refused) of them \(refused == 1 ? "was" : "were") refused and so stood in for nothing"
        case (false, false):
            ""
        }
    }

    /// Which gap the verdict counted, spelled out where a reader is looking at the numbers it is short by.
    private static func malformedLines(_ count: Int) -> [String] {
        count > 0 ? ["\(count) malformed line\(count == 1 ? "" : "s") skipped — this report is short by whatever they recorded"] : []
    }

    /// The tools a set of calls was made with, most-used first, so the wording is deterministic.
    private static func named(_ entries: [UsageLog.Entry]) -> String {
        let tools = grouped(entries, by: \.tool).map(\.0)
        guard tools.count > 1, let last = tools.last else { return tools.first ?? "" }
        return tools.dropLast().joined(separator: ", ") + " and " + last
    }

    /// Groups calls by `key`, most-used first — ties alphabetical, so two runs over one log render alike.
    private static func grouped(_ entries: [UsageLog.Entry], by key: (UsageLog.Entry) -> String) -> [(String, [UsageLog.Entry])] {
        Dictionary(grouping: entries, by: key)
            .sorted { $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count }
            .map { ($0.key, $0.value) }
    }

    /// The nearest-rank percentile of an already-sorted list.
    static func percentile(_ sorted: [Int], _ rank: Int) -> Int {
        guard !sorted.isEmpty else { return 0 }
        let index = Int((Double(rank) / 100 * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(max(0, index), sorted.count - 1)]
    }

    /// Every readable line in the log, and how many were not.
    ///
    /// A line this build cannot decode is counted and skipped rather than ending the read: the file is appended to by every version of this tool that has ever run on the machine, and one torn line from an interrupted write must not cost the other six thousand. That is a gap *within* a file that was read; a file that could not be read at all is a different fact and throws.
    ///
    /// **Absence and unreadability are told apart before the bytes are asked for.** `try?` around the read collapsed "no log yet", "no permission", and "a directory sits where the file belongs" into one empty answer that reported nothing had ever been called.
    public static func entries(at fileURL: URL) throws -> (entries: [UsageLog.Entry], malformed: Int) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return ([], 0) }
        let text: String
        do {
            text = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw UsageLogReadError.unreadable(path: fileURL.path.tildedPath, reason: unreadableReason(at: fileURL))
        }
        let decoder = JSONDecoder()
        var entries: [UsageLog.Entry] = []
        var malformed = 0
        for line in text.split(separator: "\n") where !String(line).trimmed.isEmpty {
            if let entry = try? decoder.decode(UsageLog.Entry.self, from: Data(line.utf8)) {
                entries.append(entry)
            } else {
                malformed += 1
            }
        }
        return (entries, malformed)
    }
}

public extension UsageLog.Entry {
    /// The day the log filed this call under — the timestamp's UTC date, which is the date the log is written in.
    var day: String {
        String(timestamp.prefix(10))
    }

    /// This failure's kind: the field itself where the line carries one, else inferred from its own recorded error text where that text is unambiguous — a line written before the field existed.
    ///
    /// `nil` where neither says, which the report counts as `unclassified` rather than guesses at — and `nil` on a line that succeeded, where a kind means nothing, so no reader has to remember to ask that first.
    ///
    /// **Inference never overrides a kind this build does not recognise.** `kind` is `nil` in two different cases — a line older than the field, and a line whose stored `kind` this build's `UsageFailureKind` has no case for (``unrecognizedKind`` then holds the raw text) — and only the first is what inference exists for. A line that *did* state a kind, in words a newer binary understood, is not open to being reread as whatever its error text happens to resemble; that would let a kind this build cannot place come back disguised as one it can, `input-refused` included, which is exactly the report's own excluded category.
    var classifiedFailureKind: UsageFailureKind? {
        guard !succeeded else {
            return nil
        }
        if let kind {
            return kind
        }
        guard unrecognizedKind == nil else {
            return nil
        }
        return UsageFailureKind.inferred(fromErrorText: error ?? "")
    }

    /// Whether this call was refused: a caller's own argument turned away, `input-refused` — the tool working, not the tool failing.
    ///
    /// **The one test of "refused"**, read by everything that prints the word — the headline's exclusion, `byTool`, the savings note and the status line — so it cannot mean the stored field in one place and the inferred classification in another. It reads ``classifiedFailureKind``, never `kind` alone, because a line older than the field is a refusal too when its own text says so, and a status line that crossed a deploy reads exactly such lines.
    var isRefusal: Bool {
        classifiedFailureKind == .inputRefused
    }

    /// Whether this call failed: it did not succeed, and was not a refusal — everything `simwalk usage` counts as a failure, `unclassified` and `unrecognized-kind` included, since a failure nothing can place is never assumed to be the caller's.
    var isFailure: Bool {
        !succeeded && !isRefusal
    }

    /// Whether ``classifiedFailureKind`` had to be read off `error` rather than off the stored field — a line with no `kind` at all whose error text matched a rule.
    ///
    /// Never true of a line that stored a kind, recognised or not: a stored kind is evidence of its own, and an unrecognised one is never inferred over.
    var failureKindWasInferred: Bool {
        kind == nil && classifiedFailureKind != nil
    }

    /// The label `simwalk usage`'s by-kind breakdown groups this failure under: the classified kind's own wire spelling where there is one, else one of two different reasons there is not.
    ///
    /// `unrecognized-kind` for a line whose stored `kind` this build does not know (``UsageLog/Entry/unrecognizedKind``, necessarily from a newer binary), and `unclassified` for a line with nothing stored and error text that matched no rule. Keeping the two apart is the point: once every failure site in this build is mapped, `unclassified` should only ever hold lines older than the field itself.
    var failureKindLabel: String {
        if let classifiedFailureKind {
            return classifiedFailureKind.rawValue
        }
        if unrecognizedKind != nil {
            return UsageReport.unrecognizedKindLabel
        }
        return UsageReport.unclassifiedLabel
    }
}

private extension UsageReport {
    /// Why a log that exists could not be read, in fixed words that say what would make it readable.
    ///
    /// Not `localizedDescription`: that text changes with the machine's locale, so two readers of the same refusal would disagree about what it said, and it names the failure without naming the remedy — which is the half a refusal owes (the answer contract, §5).
    static func unreadableReason(at fileURL: URL) -> String {
        var isDirectory: ObjCBool = false
        let manager = FileManager.default
        if manager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return "a directory sits where the log file belongs — move it aside, or pass --log <file>"
        }
        if !manager.isReadableFile(atPath: fileURL.path) {
            return "no permission to read it — chmod u+r the file, or pass --log <file>"
        }
        return "not readable as UTF-8 text — pass --log <file> naming a log this tool wrote"
    }
}
