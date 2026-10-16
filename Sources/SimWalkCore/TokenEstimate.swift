//
// Copyright © Agulhas Labs
//

import Foundation

/// Bytes priced in the unit a reader of an answer actually spends: tokens of context.
///
/// What this tool measures is what a walk put on disk — screenshots and accessibility trees — and what it saves is the part of that which never has to enter a model's context window. Kilobytes have to be converted in the head before they mean anything against a context limit; tokens do not, so tokens are the unit every saving is stated in.
///
/// **It is an estimate, and it says so.** Nothing here tokenizes anything: it counts bytes and divides, and every rendering carries the tilde. The ratio — four bytes a token — is the *conservative* end of what an accessibility tree costs. A tree is JSON dense with punctuation, short keys and repeated structure, which tokenizes worse than prose rather than better, so the true figure is at least the one shown. An estimate quoted as a saving must err towards claiming too little, and this one does.
public struct TokenEstimate {
    /// Bytes per token: the low end of what a JSON accessibility tree costs, so the estimate is a floor.
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

    /// How a byte-derived estimate was made, for the faces with room to say so: `43 kB of accessibility trees at 4 bytes a token`.
    public static func basis(bytes: Int, of subject: String) -> String {
        "\(ByteSize.short(bytes)) of \(subject) at \(bytesPerToken) bytes a token"
    }
}
