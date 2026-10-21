//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Vision

/// Reads the text off a capture of the mirrored phone with Vision, as lines placed in window fractions.
///
/// **Language correction is off, deliberately.** The reads exist to serve figures (`16:48`, `1,122`) exactly as drawn, and a correcting model "fixes" a figure into a word. `accurate` recognition is used because the phone's text is small and a wrong digit is worse than a slow read; the settle loop's 250 ms interval is a ceiling it is expected to meet, not a floor it may undercut.
///
/// **Only the top candidate of each observation is taken**, with its confidence, so a caller can see how sure the recogniser was. Vision answers in normalised coordinates with the origin bottom-left; they are flipped here to the top-left fractions `MirrorTextLine` documents, so nothing downstream knows Vision's convention.
public struct VisionTextReader: Sendable {
    public init() {}

    /// The lines Vision recognises in the PNG at `url`, in reading order.
    ///
    /// - Parameters:
    ///   - url: The capture.
    ///   - capturedAt: When it was taken; supplied by the caller because the core never asks the clock.
    /// - Throws: `ReadError` naming the file when it is missing, unreadable or Vision fails.
    public func read(_ url: URL, capturedAt: Date) throws -> MirrorRead {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw ReadError(file: url, cause: "the file does not exist or is not readable")
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(url: url, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw ReadError(file: url, cause: error.localizedDescription)
        }
        let lines = (request.results ?? []).compactMap { observation -> MirrorTextLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return MirrorTextLine(
                text: candidate.string,
                centreX: Double(box.midX),
                centreY: 1 - Double(box.midY),
                width: Double(box.width),
                height: Double(box.height),
                confidence: Double(candidate.confidence)
            )
        }
        return MirrorRead(path: url, pixelSize: PNGSize(contentsOf: url), capturedAt: capturedAt, lines: lines)
    }
}

extension VisionTextReader: ScreenTextRecognizing {
    public func lines(inPNGAt url: URL) throws -> [MirrorTextLine] {
        try read(url, capturedAt: Date(timeIntervalSince1970: 0)).lines
    }
}

public extension VisionTextReader {
    /// Why a capture could not be read.
    struct ReadError: Error, Equatable, CustomStringConvertible, Sendable {
        /// The capture that was being read.
        public let file: URL
        /// What went wrong, in Vision's or the file system's words.
        public let cause: String

        public var description: String {
            "could not read text from \(file.path): \(cause)"
        }
    }
}
