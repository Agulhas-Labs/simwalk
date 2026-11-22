//
// Copyright © Agulhas Labs
//

import Foundation

/// Bytes priced in the unit a reader of an answer actually spends: tokens of context.
///
/// A saving is stated in tokens because kilobytes have to be converted in the head before they mean anything against a context limit. Screenshots are priced by their pixels (``ImageTokenEstimate``); what this prices by bytes is the text an answer served, which is subtracted from them (accessibility trees are not priced at all: no agent reads raw trees as the alternative to an answer, SimWalk#293).
///
/// **It is an estimate, and it says so.** Nothing here tokenizes anything: it counts bytes and divides, and every rendering carries the tilde. Four bytes a token is typical of English text; an answer dense with paths and identifiers tokenizes worse, so its cost, and therefore the saving, is approximate rather than a strict floor.
public struct TokenEstimate {
    /// Bytes per token, typical of English text.
    public static let bytesPerToken = 4

    /// The tokens `bytes` amount to, at the ratio above.
    public static func tokens(forBytes bytes: Int) -> Int {
        max(0, bytes) / bytesPerToken
    }

    /// `count` tokens with the unit attached: `~800 tokens`, `~4.5k tokens`, `~54k tokens`, `~2.2M tokens`.
    public static func short(_ count: Int) -> String {
        "\(magnitude(count)) token\(count == 1 ? "" : "s")"
    }

    /// The same figure without its unit — `~4.1k` — for a clause whose sentence has already named the unit once.
    public static func magnitude(_ count: Int) -> String {
        if count < 1000 {
            return "~\(count)"
        }
        if count < 10000 {
            return String(format: "~%.1fk", Double(count) / 1000)
        }
        if count < 1_000_000 {
            return "~\(count / 1000)k"
        }
        return String(format: "~%.1fM", Double(count) / 1_000_000)
    }
}
