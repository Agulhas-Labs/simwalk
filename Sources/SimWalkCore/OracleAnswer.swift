//
// Copyright © Agulhas Labs
//

import Foundation

/// What a value oracle said about one request: the expected value under each window with what it was computed from, or why there is no answer.
///
/// **A failure is never a match or a mismatch.** A timeout, a non-zero exit, a reply that does not parse or names no value for a window asked about — each is `failed` with its reason, and a check renders it `oracle failed`, never `matches none`.
public enum OracleAnswer: Equatable, Sendable {
    /// The oracle's values, keyed by window, with the unit and the attribution it gave.
    case reply(values: [String: Double], unit: String?, attribution: String?)
    /// No answer, and why.
    case failed(reason: String)

    /// The answer one reply line is: `{"values": {"midnight": 3326, "rolling24h": 2703}, "unit": "count", "attribution": "…"}`, or `{"error": "…"}`.
    public static func parsing(_ line: String) -> OracleAnswer {
        guard let wire = try? JSONDecoder().decode(Wire.self, from: Data(line.utf8)) else {
            return .failed(reason: "its reply is not a JSON object of values: '\(line.prefix(80))'")
        }
        if let error = wire.error {
            return .failed(reason: "it answered: \(error)")
        }
        guard let values = wire.values else {
            return .failed(reason: "its reply names neither 'values' nor 'error'")
        }
        return .reply(values: values, unit: wire.unit, attribution: wire.attribution)
    }
}

extension OracleAnswer {
    /// The reply's shape on the wire; keys it does not name are ignored.
    private struct Wire: Decodable {
        let values: [String: Double]?
        let unit: String?
        let attribution: String?
        let error: String?
    }
}
