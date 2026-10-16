//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// The answer a mirror step renders: its header's method, a verdict for each outcome, and the residue's per-line spelling.
struct MirrorObservationSummaryTests {
    private static let window = MirrorWindowFrame(windowID: 7, x: 0, y: 0, width: 383, height: 843)
    private static let utc = TimeZone(identifier: "UTC") ?? .gmt
    private static let eventAt = Date(timeIntervalSince1970: 1_760_000_000)

    private func observation(action: MirrorAction? = nil, before: MirrorRead?, read: MirrorRead, reason: MirrorSettle.Reason? = nil, after: TimeInterval = 0.75) -> MirrorObservation {
        let served = MirrorRead(path: URL(fileURLWithPath: "/caps/a.png"), pixelSize: PNGSize(width: 1000, height: 2000), capturedAt: Self.eventAt.addingTimeInterval(after), lines: read.lines)
        return MirrorObservation(action: action, window: Self.window, before: before, read: served, reason: reason, eventAt: Self.eventAt, reads: 3, boundMilliseconds: 3000)
    }

    private func tap() throws -> MirrorAction {
        try .tap(MirrorFraction(x: 0.5, y: 0.62))
    }

    /// The header names the action, the window and the method, and never claims what the screen shows.
    @Test
    func theHeaderSaysTheTextWasReadByOCR() throws {
        let answer = try MirrorObservationSummary.answer(observation(action: tap(), before: MirrorReadFixture.screen(["A"]), read: MirrorReadFixture.screen(["B"])), timeZone: Self.utc)

        #expect(answer.header == "mirror tap .50,.62 · iPhone Mirroring 383×843 pt · text read by OCR")
        #expect(!answer.text.contains("screen shows"))
    }

    /// A settled step is ok, with the counts since before and the time and reads it took.
    @Test
    func aSettledStepIsUnqualified() throws {
        let read = MirrorReadFixture.screen(["Rows", "14 wk"])
        let answer = try MirrorObservationSummary.answer(observation(action: tap(), before: MirrorReadFixture.screen(["Hub", "Rows"]), read: read), timeZone: Self.utc)

        #expect(answer.verdict == .unqualified("3 lines · +1 −1 since before · settled in 750 ms over 3 reads"))
    }

    /// A read has no before and so no "since before".
    @Test
    func aReadHasNoSinceBefore() {
        let answer = MirrorObservationSummary.answer(observation(before: nil, read: MirrorReadFixture.screen(["A"])), timeZone: Self.utc)

        #expect(answer.verdict == .unqualified("2 lines · settled in 750 ms over 3 reads"))
        #expect(!(answer.residue.first ?? "").contains("after the event"))
    }

    /// Each unsettled outcome is qualified with its bound; neither passes cleanly.
    @Test
    func anUnsettledStepIsQualified() throws {
        let read = MirrorReadFixture.screen(["A"])
        let same = try observation(action: tap(), before: read, read: read, reason: .noVisibleChange)
        let moving = try observation(action: tap(), before: read, read: MirrorReadFixture.screen(["B"]), reason: .stillChanging)

        #expect(MirrorObservationSummary.answer(same, timeZone: Self.utc).verdict == .qualified(["no visible text changed within 3000 ms"], detail: "2 lines · +0 −0 since before"))
        #expect(MirrorObservationSummary.answer(moving, timeZone: Self.utc).verdict == .qualified(["not settled within 3000 ms; the last read is shown"], detail: "2 lines · +1 −1 since before"))
    }

    /// No lines read is never a clean pass, whatever settled.
    @Test
    func noTextIsQualifiedNeverOk() throws {
        let answer = try MirrorObservationSummary.answer(observation(action: tap(), before: nil, read: MirrorReadFixture.read([])), timeZone: Self.utc)

        #expect(answer.verdict == .qualified(["no text read: the screen may be blank, locked, or Screen Recording is not granted to this process"], detail: ""))
        #expect(answer.verdict.isQualified)
    }

    /// The first residue line is the capture with its size, clock time and delay; then each line with `+` for an added one (a doubtful line is never compared, so never added), three-decimal centre, two-decimal size and `?` for doubt.
    @Test
    func theResidueSpellsEachLine() throws {
        let doubtful = MirrorTextLine(text: "Rowing", centreX: 0.512, centreY: 0.118, width: 0.4, height: 0.02, confidence: 0.3)
        let known = MirrorTextLine(text: "Rows", centreX: 0.5, centreY: 0.3, width: 0.3, height: 0.02, confidence: 0.9)
        let before = MirrorReadFixture.read([known])
        let answer = try MirrorObservationSummary.answer(observation(action: tap(), before: before, read: MirrorReadFixture.read([doubtful, known])), timeZone: Self.utc)

        #expect(answer.residue == [
            "capture /caps/a.png · 1000×2000 px · 08:53:20.750 (+750 ms after the event)",
            "  .512,.118 .40×.02 ?0.30  Rowing",
            "  .500,.300 .30×.02  Rows",
        ])
    }

    /// Gone texts come last, at most ten quoted and the rest counted, each clipped to 40 characters.
    @Test
    func goneTextsAreClipped() throws {
        let gone = (1 ... 12).map { "Old \($0)" } + [String(repeating: "x", count: 60)]
        let answer = try MirrorObservationSummary.answer(observation(action: tap(), before: MirrorReadFixture.screen(gone), read: MirrorReadFixture.screen([])), timeZone: Self.utc)
        let line = answer.residue.last ?? ""

        #expect(line.hasPrefix("gone: \"Old 1\", \"Old 2\""))
        #expect(line.contains("\"Old 10\", and 3 more"))
        #expect(!line.contains("Old 11"))
        #expect(!line.contains(String(repeating: "x", count: 41)))
    }

    /// `match` filters the listed lines, case-insensitively, while the verdict still counts the whole screen.
    @Test
    func matchFiltersTheLinesNotTheCounts() throws {
        let read = MirrorReadFixture.screen(["Hub", "Rowing", "14 wk"])
        let answer = try MirrorObservationSummary.answer(observation(action: tap(), before: MirrorReadFixture.screen(["Menus"]), read: read), match: "ROW", timeZone: Self.utc)

        #expect(answer.verdict == .unqualified("4 lines · +3 −1 since before · settled in 750 ms over 3 reads"))
        #expect(answer.residue.count == 3)
        #expect(answer.residue[1].hasSuffix("Rowing"))
    }

    /// Only as many occurrences as `added` holds are marked, and never a status-band line saying the same.
    @Test
    func anUnchangedDuplicateOfAnAddedLineIsNotMarked() throws {
        let before = MirrorReadFixture.read([MirrorReadFixture.line("Rowing", y: 0.3)])
        let read = MirrorReadFixture.read([MirrorReadFixture.line("Rowing", y: 0.02), MirrorReadFixture.line("Rowing", y: 0.3), MirrorReadFixture.line("Rowing", y: 0.5)])
        let answer = try MirrorObservationSummary.answer(observation(action: tap(), before: before, read: read), timeZone: Self.utc)

        #expect(answer.residue.dropFirst().map { $0.prefix(1) } == [" ", " ", "+"])
    }

    /// `+` marking is the set `change` counts: a leading-glyph variant of a before line is not marked, a real addition is.
    @Test
    func markingAgreesWithChangeOnALeadingGlyphVariant() throws {
        let before = MirrorReadFixture.read([MirrorReadFixture.line("J Declining", y: 0.3), MirrorReadFixture.line("Rows", y: 0.4)])
        let read = MirrorReadFixture.read([MirrorReadFixture.line("↓ Declining", y: 0.3), MirrorReadFixture.line("Rows", y: 0.4), MirrorReadFixture.line("Rowing", y: 0.5)])
        let answer = try MirrorObservationSummary.answer(observation(action: tap(), before: before, read: read), timeZone: Self.utc)

        #expect(read.change(from: before).added == ["Rowing"])
        #expect(answer.residue.dropFirst().map { $0.prefix(1) } == [" ", " ", "+"])
    }

    /// A step that settled on the same text in other places says so rather than looking like a quiet no-op.
    @Test
    func settlingOnlyBecauseLinesMovedIsSaid() throws {
        let before = MirrorReadFixture.read([MirrorReadFixture.line("Rows", y: 0.3)])
        let moved = MirrorReadFixture.read([MirrorReadFixture.line("Rows", y: 0.5)])
        let answer = try MirrorObservationSummary.answer(observation(action: tap(), before: before, read: moved), timeZone: Self.utc)

        #expect(answer.verdict == .unqualified("1 line · +0 −0 since before · text unchanged; lines moved · settled in 750 ms over 3 reads"))
    }

    /// One screenshot is weighed when the capture's size is known, none when it is not.
    @Test
    func theWeighingIsOneScreenshot() {
        let weighed = MirrorObservationSummary.answer(observation(before: nil, read: MirrorReadFixture.screen(["A"])), timeZone: Self.utc)
        let unknown = MirrorObservationSummary.answer(MirrorObservation(action: nil, window: Self.window, before: nil, read: MirrorReadFixture.screen(["A"]), reason: nil, eventAt: Self.eventAt, reads: 2, boundMilliseconds: 3000), timeZone: Self.utc)

        #expect(weighed.weighing?.screenshotTokens == [ImageTokenEstimate.tokens(of: PNGSize(width: 1000, height: 2000))])
        #expect(unknown.weighing == nil)
    }

    /// Every action spells its label for the header.
    @Test
    func actionLabels() throws {
        let centre = try MirrorFraction(x: 0.5, y: 0.5)

        #expect(MirrorAction.scroll(lines: 5, horizontal: false, position: centre).label == "scroll 5 at .50,.50")
        #expect(MirrorAction.menu(.homeScreen).label == "menu Home Screen")
        #expect(try MirrorAction.swipe(from: centre, to: MirrorFraction(x: 0.5, y: 0.2), milliseconds: 400).label == "swipe .50,.50 to .50,.20 in 400 ms")
    }
}
