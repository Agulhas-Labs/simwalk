//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// Reading order, agreement and change between two reads of the mirrored phone, on scripted lines.
struct MirrorReadTests {
    private typealias Fixture = MirrorReadFixture

    @Test("Rows run top to bottom and lines in a row left to right")
    func readingOrder() {
        let read = Fixture.read([
            Fixture.line("c", x: 0.8, y: 0.40),
            Fixture.line("b", x: 0.7, y: 0.305),
            Fixture.line("a", x: 0.2, y: 0.30),
            Fixture.line("d", x: 0.5, y: 0.50),
        ])

        #expect(read.lines.map(\.text) == ["a", "b", "c", "d"])
    }

    @Test("A line further than half the smaller height from the row's is a row of its own")
    func rowThreshold() {
        let sameRow = Fixture.read([Fixture.line("right", x: 0.9, y: 0.291), Fixture.line("left", x: 0.1, y: 0.30)])
        let ownRow = Fixture.read([Fixture.line("right", x: 0.9, y: 0.289), Fixture.line("left", x: 0.1, y: 0.30)])

        #expect(sameRow.lines.map(\.text) == ["left", "right"])
        #expect(ownRow.lines.map(\.text) == ["right", "left"])
    }

    @Test("Agreement ignores the status band")
    func agreementIgnoresBand() {
        let a = Fixture.screen(clock: "09:41", ["Rows", "1,122"])
        let b = Fixture.screen(clock: "09:42", ["Rows", "1,122"])

        #expect(a.agrees(with: b))
        #expect(a.change(from: b).isEmpty)
    }

    @Test("Agreement needs the same texts in the same order")
    func agreementNeedsText() {
        let a = Fixture.screen(["Rows", "1,122"])

        #expect(!a.agrees(with: Fixture.screen(["Rows", "1,123"])))
        #expect(!a.agrees(with: Fixture.screen(["Rows"])))
    }

    @Test("Agreement holds at the position tolerance and fails beyond it")
    func agreementTolerance() {
        let base = Fixture.read([Fixture.line("Rows", y: 0.30)])
        let edge = Fixture.read([Fixture.line("Rows", y: 0.30 + MirrorRead.positionTolerance - 0.0005)])
        let beyond = Fixture.read([Fixture.line("Rows", y: 0.30 + MirrorRead.positionTolerance + 0.002)])
        let sideways = Fixture.read([Fixture.line("Rows", x: 0.5 + MirrorRead.positionTolerance + 0.002, y: 0.30)])

        #expect(base.agrees(with: edge))
        #expect(!base.agrees(with: beyond))
        #expect(!base.agrees(with: sideways))
    }

    @Test("Added and gone are multisets by text")
    func addedAndGone() {
        let before = Fixture.screen(["a", "a", "b"])
        let after = Fixture.screen(["a", "b", "b", "c"])

        let change = after.change(from: before)

        #expect(change.added == ["b", "c"])
        #expect(change.gone == ["a"])
    }

    @Test("A line inside the band is served but never counted as added or gone")
    func bandLinesServed() {
        let read = Fixture.screen(clock: "09:41", ["Rows"])

        #expect(read.lines.contains { $0.text == "09:41" })
        #expect(read.change(from: Fixture.screen(clock: "10:00", ["Rows"])).isEmpty)
    }

    /// The pairs measured live on a still screen: OCR drew each differently on consecutive reads.
    @Test(
        "Live OCR jitter on a still screen is the same text",
        arguments: [
            ("Is down 3.", "is down 3."),
            ("J Declining", "1 Declining"),
            ("1 Declining", "↓ Declining"),
            ("↓ Declining", "J Declining"),
            ("1 0ct.", "10ct."),
            ("128 avg • 78-149 bpm", "128 avg 78-149 bpm"),
            ("• Rowing", "Rowing"),
            ("5.00 km • 128 bpm", "5.00 km \u{FFFE} 128 bpm"),
        ]
    )
    func jitterAgrees(first: String, second: String) {
        let a = Fixture.read([Fixture.line(first, y: 0.3)])
        let b = Fixture.read([Fixture.line(second, y: 0.3)])

        #expect(a.agrees(with: b))
        #expect(b.change(from: a).isEmpty)
        #expect(a.change(from: b).isEmpty)
    }

    @Test("A digit or a word that differs is a real change", arguments: [("34 min", "35 min"), ("Rowing", "Cycling"), ("34min", "35min"), ("Rows", "Rowe"), ("2 Selected", "3 Selected"), ("5 min ago", "6 min ago"), ("+3.2%", "-3.2%"), ("↑ 2.5 kg", "↓ 2.5 kg"), ("↑ Rising", "↓ Declining")])
    func realChangesStay(first: String, second: String) {
        let a = Fixture.read([Fixture.line(first, y: 0.3)])
        let b = Fixture.read([Fixture.line(second, y: 0.3)])

        #expect(!a.agrees(with: b))
        #expect(b.change(from: a).added == [second])
        #expect(b.change(from: a).gone == [first])
    }

    @Test("A leading glyph is forgiven only with four characters after it")
    func leadingGlyphNeedsFourAfter() {
        let short = Fixture.read([Fixture.line("A bcd", y: 0.3)])
        let shortVariant = Fixture.read([Fixture.line("B bcd", y: 0.3)])

        #expect(!short.agrees(with: shortVariant))
    }

    @Test("A low-confidence line appearing or vanishing is no change and does not break agreement")
    func doubtfulLinesAreIgnored() {
        let soup = MirrorTextLine(text: "• aall", centreX: 0.5, centreY: 0.5, width: 0.1, height: 0.02, confidence: 0.3)
        let plain = Fixture.read([Fixture.line("Rows", y: 0.3)])
        let withSoup = Fixture.read([Fixture.line("Rows", y: 0.3), soup])

        #expect(plain.agrees(with: withSoup))
        #expect(withSoup.agrees(with: plain))
        #expect(withSoup.change(from: plain).isEmpty)
        #expect(plain.change(from: withSoup).isEmpty)
        #expect(withSoup.lines.contains(soup))
    }

    @Test("A clock at y 0.078 in the Mirroring window is inside the status band")
    func mirroringClockIsIgnored() {
        let before = Fixture.read([Fixture.line("11:45", y: 0.077), Fixture.line("58", x: 0.9, y: 0.078), Fixture.line("Rows", y: 0.132)])
        let after = Fixture.read([Fixture.line("11:46", y: 0.077), Fixture.line("57", x: 0.9, y: 0.078), Fixture.line("Rows", y: 0.132)])

        #expect(after.change(from: before).isEmpty)
        #expect(before.agrees(with: after))
        #expect(after.comparableLines.map(\.text) == ["Rows"])
    }
}
