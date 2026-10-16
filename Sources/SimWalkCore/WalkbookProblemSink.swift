//
// Copyright © Agulhas Labs
//

import Foundation

/// Where a walkbook's key problems collect while it decodes, so an unknown key stops meaning "abort before anything else can be reported" (round 2) — and, since round 4, a missing required key or a route step naming no step too, each decoded past with a placeholder that `WalkbookLoader` never lets out (`StrictKeyDecoding.required`).
///
/// `checkUnknownKeys` used to throw the moment it found one, which aborted the whole decode — so a misspelled key hid every other `WalkbookProblem` behind it, contradicting `validate`'s own promise of "every problem at once". A `JSONDecoder` has no way to hand back a partial result from a failed decode, and an unknown key is never load-bearing for any field's value — silently not looking it up is safe — so `Decoder.userInfo` carries this sink into every nested `init(from:)`, and `checkUnknownKeys` records into it instead of throwing whenever one is installed. `WalkbookLoader.load(from:source:)` installs one and merges what it collects with the walkbook's structural problems; every other caller — a direct `JSONDecoder().decode(Walkbook.self, …)`, exactly what every `StrictKeyDecodingTests` case does — installs none, so an unknown key still throws immediately there, unchanged.
///
/// `@unchecked`: `JSONDecoder.userInfo` requires `Sendable` values, but this is used the way `userInfo` always is — created immediately before one synchronous `decode(_:from:)` call and read back immediately after, never touched from more than one thread.
final class WalkbookProblemSink: @unchecked Sendable {
    private(set) var problems: [WalkbookProblem] = []

    func record(_ problem: WalkbookProblem) {
        problems.append(problem)
    }
}

extension CodingUserInfoKey {
    /// The key `WalkbookProblemSink` installs itself under in a decoder's `userInfo`.
    static let walkbookProblemSink: CodingUserInfoKey = {
        guard let key = CodingUserInfoKey(rawValue: "com.agulhaslabs.simwalk.walkbookProblemSink") else {
            preconditionFailure("a non-empty string literal always makes a valid CodingUserInfoKey")
        }
        return key
    }()
}
