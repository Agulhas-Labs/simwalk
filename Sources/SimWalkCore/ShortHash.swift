//
// Copyright © Agulhas Labs
//

import Foundation

/// The leading digits of a hash, for reading — long enough to identify a build or a plan in a header line, never used for comparison.
///
/// One generator rather than a `prefix` at each call site, and one *length* rather than one per kind of hash: a header naming a build and a walkbook side by side reads as a pair of identities, and two different lengths in the same line read as two different kinds of thing. Provenance is the only thing a hash is ever printed for (the answer contract's wording rule), so the full digest stays in the manifest, where comparison happens.
public struct ShortHash {
    /// How many leading hex digits a printed hash carries.
    public static let digits = 8

    /// `hash` as it is printed in an answer.
    public static func of(_ hash: String) -> String {
        String(hash.prefix(digits))
    }
}
