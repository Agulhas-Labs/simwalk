//
// Copyright © Agulhas Labs
//

import Foundation

/// One question for a value oracle: what should this figure read, on this screen, in this state, at the moment it was captured, under each of these windows.
///
/// Written to the oracle as **one JSON line** — `{"capturedAt":"2026-09-29T08:15:02.125Z","figure":"steps-today","locale":"en_US","screen":"today","state":"light","windows":["midnight","rolling24h"]}` — keys sorted. The windows are the walkbook's strings, passed through: SimWalk never interprets one.
public struct OracleRequest: Codable, Equatable, Sendable {
    public let figure: String
    public let windows: [String]
    /// The capture's time as ISO 8601 with milliseconds, which is what a rolling window is computed back from.
    public let capturedAt: String
    public let locale: String
    public let screen: String
    /// The state's slug, as the bundle files it.
    public let state: String

    public init(figure: String, windows: [String], capturedAt: Date, locale: String, screen: String, state: String) {
        self.figure = figure
        self.windows = windows
        self.capturedAt = Timestamp.string(from: capturedAt)
        self.locale = locale
        self.screen = screen
        self.state = state
    }

    /// The request as the one line the oracle reads, without its newline.
    public var jsonLine: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Encoding four strings and a list of strings cannot fail.
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}
