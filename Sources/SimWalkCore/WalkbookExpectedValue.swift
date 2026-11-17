//
// Copyright © Agulhas Labs
//

import Foundation

public extension Walkbook {
    /// One element a screen's `expectValues` says must read a value: the node named `label` (by its label or its identifier) reads `value` (SimWalk#259).
    ///
    /// Both are compared whole against the captured node, as `expect` and `expectMenu` are — see `ExpectedValueCheck`. Decoded strictly, like a route step's payload, so `{"label": "X", "val": "Done"}` is refused by name rather than read as an entry with no value to check.
    struct ExpectedValue: Codable, Equatable, Sendable {
        /// The label or accessibility identifier of the element.
        public var label: String
        /// What the element's accessibility value must read.
        public var value: String

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: AnyCodingKey.self)
            try StrictKeyDecoding.checkUnknownKeys(in: container, allowing: ["label", "value"], decoder: decoder)
            label = try StrictKeyDecoding.required(String.self, forKey: AnyCodingKey("label"), in: container, decoder: decoder, placeholder: "")
            value = try StrictKeyDecoding.required(String.self, forKey: AnyCodingKey("value"), in: container, decoder: decoder, placeholder: "")
        }
    }
}
