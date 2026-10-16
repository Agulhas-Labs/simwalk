//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkDriver
import Testing

/// Vision's reading of a capture, against a PNG made for the purpose.
///
/// `Fixtures/mirror-ocr.png` is 660×1430 px, white, drawn once by a throwaway AppKit script in the system font, one line centred horizontally at each of these vertical positions (fractions of the height, top-left origin): `09:41` at 0.028 (inside the status band), `Trend` at 0.210, `1,122 samples` at 0.420, `16:48 of 22:13 in a zone` at 0.559, `synced 09:34 today` at 0.699. It holds no personal data.
struct VisionTextReaderTests {
    private static let expected: [(text: String, centreY: Double)] = [
        ("09:41", 0.028),
        ("Trend", 0.210),
        ("1,122 samples", 0.420),
        ("16:48 of 22:13 in a zone", 0.559),
        ("synced 09:34 today", 0.699),
    ]

    private static var fixture: URL {
        get throws {
            let directory = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
            return directory.appendingPathComponent("mirror-ocr.png")
        }
    }

    @Test("Figures come back as drawn, in reading order, at the places they were drawn")
    func readsFiguresExactly() throws {
        let when = Date(timeIntervalSince1970: 42)

        let read = try VisionTextReader().read(Self.fixture, capturedAt: when)

        #expect(read.lines.map(\.text) == Self.expected.map(\.text))
        for (line, want) in zip(read.lines, Self.expected) {
            #expect(abs(line.centreY - want.centreY) < 0.03, "\(line.text) at \(line.centreY)")
            #expect(abs(line.centreX - 0.5) < 0.03, "\(line.text) at x \(line.centreX)")
            #expect(line.confidence > 0.5, "\(line.text) confidence \(line.confidence)")
        }
        #expect(read.pixelSize == PNGSize(width: 660, height: 1430))
        #expect(read.capturedAt == when)
        #expect(read.lines.first.map { $0.centreY < MirrorRead.statusBandFraction } == true)
    }

    @Test("A missing file throws an error naming the file")
    func missingFile() {
        let url = URL(fileURLWithPath: "/nonexistent/mirror.png")

        let error = #expect(throws: VisionTextReader.ReadError.self) {
            try VisionTextReader().read(url, capturedAt: Date(timeIntervalSince1970: 0))
        }

        #expect(error?.file == url)
        #expect(error?.description.contains("/nonexistent/mirror.png") == true)
    }
}
