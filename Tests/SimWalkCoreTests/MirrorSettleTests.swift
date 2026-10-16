//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// When a step on the mirrored phone is answered, replayed from scripted reads.
struct MirrorSettleTests {
    private typealias Fixture = MirrorReadFixture

    private let old = Fixture.screen(["Rows", "1,122"])
    private let new = Fixture.screen(["Rows", "1,130"])

    @Test("Two agreeing reads that differ from before settle the step")
    func settlesWithChange() {
        var settle = MirrorSettle(before: old, boundMilliseconds: 3000)

        #expect(settle.take(new, elapsedMilliseconds: 250) == .readAgain)
        #expect(settle.take(new, elapsedMilliseconds: 500) == .settled(new))
        #expect(settle.reads == 2)
    }

    @Test("A read still changing is read again until the pair agrees")
    func waitsOutTransition() {
        let mid = Fixture.screen(["Loading"])
        var settle = MirrorSettle(before: old, boundMilliseconds: 3000)

        #expect(settle.take(mid, elapsedMilliseconds: 250) == .readAgain)
        #expect(settle.take(new, elapsedMilliseconds: 500) == .readAgain)
        #expect(settle.take(new, elapsedMilliseconds: 750) == .settled(new))
    }

    @Test("Reads that agree with before are no visible change at the bound")
    func noVisibleChange() {
        var settle = MirrorSettle(before: old, boundMilliseconds: 1000)

        #expect(settle.take(old, elapsedMilliseconds: 250) == .readAgain)
        #expect(settle.take(old, elapsedMilliseconds: 500) == .readAgain)
        #expect(settle.take(old, elapsedMilliseconds: 1000) == .unsettled(old, .noVisibleChange))
    }

    @Test("A screen that never holds still is still changing at the bound")
    func stillChanging() {
        var settle = MirrorSettle(before: old, boundMilliseconds: 750)
        let reads = (1 ... 3).map { Fixture.screen(["Count \($0)"]) }

        #expect(settle.take(reads[0], elapsedMilliseconds: 250) == .readAgain)
        #expect(settle.take(reads[1], elapsedMilliseconds: 500) == .readAgain)
        #expect(settle.take(reads[2], elapsedMilliseconds: 750) == .unsettled(reads[2], .stillChanging))
    }

    @Test("With no before-read, two agreeing reads settle")
    func noBefore() {
        var settle = MirrorSettle(before: nil, boundMilliseconds: 3000)

        #expect(settle.take(old, elapsedMilliseconds: 0) == .readAgain)
        #expect(settle.take(old, elapsedMilliseconds: 250) == .settled(old))
    }

    @Test("A clock ticking inside the band alone is not a change")
    func clockIsNotAChange() {
        let ticked = Fixture.screen(clock: "09:42", ["Rows", "1,122"])
        var settle = MirrorSettle(before: old, boundMilliseconds: 500)

        #expect(settle.take(ticked, elapsedMilliseconds: 250) == .readAgain)
        #expect(settle.take(ticked, elapsedMilliseconds: 500) == .unsettled(ticked, .noVisibleChange))
    }

    @Test("A doubtful glyph-soup line coming and going does not block settling")
    func doubtfulLineDoesNotBlockSettling() {
        let soup = MirrorTextLine(text: "••0•00", centreX: 0.3, centreY: 0.5, width: 0.1, height: 0.02, confidence: 0.3)
        let withSoup = MirrorRead(path: new.path, pixelSize: nil, capturedAt: new.capturedAt, lines: new.lines + [soup])
        var settle = MirrorSettle(before: old, boundMilliseconds: 3000)

        #expect(settle.take(new, elapsedMilliseconds: 250) == .readAgain)
        #expect(settle.take(withSoup, elapsedMilliseconds: 500) == .settled(withSoup))
    }

    @Test("Reads of a still screen that differ only by OCR jitter are no visible change")
    func jitterIsNoVisibleChange() {
        let before = Fixture.read([Fixture.line("Is down 3.", y: 0.3), Fixture.line("J Declining", y: 0.4)])
        let jittered = Fixture.read([Fixture.line("is down 3.", y: 0.3), Fixture.line("↓ Declining", y: 0.4)])
        var settle = MirrorSettle(before: before, boundMilliseconds: 3000)

        #expect(settle.take(jittered, elapsedMilliseconds: 250) == .readAgain)
        #expect(settle.take(before, elapsedMilliseconds: 500) == .readAgain)
        #expect(settle.take(jittered, elapsedMilliseconds: 3000) != .readAgain)
    }
}
