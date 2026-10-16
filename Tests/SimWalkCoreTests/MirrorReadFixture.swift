//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Scripted lines and reads for the mirror suites, so each test states only what it is about.
struct MirrorReadFixture {
    static let epoch = Date(timeIntervalSince1970: 0)

    static func line(_ text: String, x: Double = 0.5, y: Double, height: Double = 0.02) -> MirrorTextLine {
        MirrorTextLine(text: text, centreX: x, centreY: y, width: 0.3, height: height, confidence: 0.9)
    }

    static func read(_ lines: [MirrorTextLine]) -> MirrorRead {
        MirrorRead(path: URL(fileURLWithPath: "/tmp/x.png"), pixelSize: nil, capturedAt: epoch, lines: lines)
    }

    /// A screen with a clock in the status band and a body of two lines.
    static func screen(clock: String = "09:41", _ body: [String]) -> MirrorRead {
        read([line(clock, y: 0.02)] + body.enumerated().map { line($1, y: 0.3 + Double($0) * 0.1) })
    }
}
