//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// The burst answer: one line a frame, each against the one before, qualified when it stopped or read nothing.
struct MirrorBurstSummaryTests {
    private static let window = MirrorWindowFrame(windowID: 7, x: 0, y: 0, width: 383, height: 843)

    private func frame(_ index: Int, _ milliseconds: Int, _ body: [String], size: PNGSize? = PNGSize(width: 1000, height: 2000)) -> MirrorBurst.Frame {
        let read = MirrorReadFixture.screen(body)
        return MirrorBurst.Frame(index: index, millisecondsSinceTap: milliseconds, read: MirrorRead(path: read.path, pixelSize: size, capturedAt: read.capturedAt, lines: read.lines))
    }

    private func burst(_ frames: [MirrorBurst.Frame], requested: Int? = nil, stoppedBy: MirrorFocusRefusal? = nil) throws -> MirrorBurst {
        try MirrorBurst(point: MirrorFraction(x: 0.5, y: 0.62), window: Self.window, requested: requested ?? frames.count, frames: frames, stoppedBy: stoppedBy, directory: URL(fileURLWithPath: "/caps/burst"))
    }

    /// The header and the frame lines: the first against nothing, the rest against the frame before, `+` and `−` sides in order.
    @Test
    func eachFrameIsComparedWithTheOneBefore() throws {
        let answer = try MirrorBurstSummary.answer(burst([
            frame(1, 120, ["Reading the logbook"]),
            frame(2, 260, ["Reading the logbook", "Rows"]),
            frame(3, 412, ["Rows", "14 wk"]),
        ]))

        #expect(answer.header == "mirror burst tap .50,.62 · 3 frames · iPhone Mirroring 383×843 pt · text read by OCR")
        #expect(answer.verdict == .unqualified("3 of 3 frames"))
        #expect(answer.residue == [
            "frames /caps/burst",
            "f01 +120 ms  +1 −0  + \"Reading the logbook\"",
            "f02 +260 ms  +1 −0  + \"Rows\"",
            "f03 +412 ms  +1 −1  + \"14 wk\" · − \"Reading the logbook\"",
        ])
        #expect(answer.weighing?.screenshotTokens.count == 3)
    }

    /// Texts are clipped to 40 characters and each side to five, the rest counted.
    @Test
    func sidesAreClipped() throws {
        let many = (1 ... 7).map { "Row \($0)" } + [String(repeating: "y", count: 60)]
        let answer = try MirrorBurstSummary.answer(burst([frame(1, 100, many)]))
        let line = answer.residue.last ?? ""

        #expect(line.contains("\"Row 5\", and 3 more"))
        #expect(!line.contains("Row 6"))
        #expect(!line.contains(String(repeating: "y", count: 41)))
    }

    /// One frame is not "1 frames".
    @Test
    func oneFrameIsSingular() throws {
        let answer = try MirrorBurstSummary.answer(burst([frame(1, 100, ["A"])], requested: 1))

        #expect(answer.header.contains(" 1 frame ·"))
        #expect(answer.text.contains("1 of 1 frame"))
        #expect(!answer.text.contains("1 of 1 frames"))
    }

    /// A stopped burst is qualified naming the frame and what was frontmost, and says how many of the frames it took.
    @Test
    func aStoppedBurstIsQualified() throws {
        let answer = try MirrorBurstSummary.answer(burst([frame(1, 100, ["A"]), frame(2, 220, ["B"])], requested: 5, stoppedBy: MirrorFocusRefusal(frontmost: "Safari", moment: .beforeFrame(3))))

        #expect(answer.verdict == .qualified(["stopped before frame 3: Safari was frontmost"], detail: "2 of 5 frames"))
    }

    /// A frame that read no text qualifies the burst.
    @Test
    func aBlankFrameIsQualified() throws {
        let blank = MirrorBurst.Frame(index: 2, millisecondsSinceTap: 200, read: MirrorReadFixture.read([]))
        let answer = try MirrorBurstSummary.answer(burst([frame(1, 100, ["A"]), blank]))

        #expect(answer.verdict.isQualified)
        #expect(answer.verdict.line.contains("no text read in frame 2"))
    }
}
