//
// Copyright © Agulhas Labs
//

import Foundation

/// A `CodingKey` that accepts any string, so a keyed container's `allKeys` answers *every* key the underlying JSON object actually holds.
///
/// A fixed `CodingKeys` enum cannot answer that question — its `init?(stringValue:)` returns `nil` for anything it does not declare, so `allKeys` on a container keyed by one silently reports only the keys it already recognised. Reading a JSON object through this key instead is what makes `StrictKeyDecoding` possible: every key survives into `allKeys`, recognised or not, so a decoder can tell the two apart.
struct AnyCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? {
        nil
    }

    /// For a known field name a decoder is about to look up — never fails, because the caller is naming its own key.
    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        // JSON objects are keyed by string; nothing here is ever addressed by index.
        nil
    }
}
