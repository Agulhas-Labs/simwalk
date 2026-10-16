//
// Copyright © Agulhas Labs
//

import Foundation

/// The small pieces of wording every rule's rows share: how a screen's rows are grouped, how a long label is cut, how a position is written.
struct AuditRowFormat {
    /// Screens in the order they were first seen, so the report follows the walk rather than the alphabet.
    static func screensInOrder<Item>(_ items: [Item], screen: (Item) -> String) -> [(String, [Item])] {
        var order: [String] = []
        var grouped: [String: [Item]] = [:]
        for item in items {
            let id = screen(item)
            if grouped[id] == nil {
                order.append(id)
            }
            grouped[id, default: []].append(item)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    /// A row's label is every descendant's text joined, so it is long by construction — enough to recognise the row is enough.
    static func trim(_ label: String) -> String {
        label.count <= 56 ? label : String(label.prefix(55)) + "…"
    }

    static func round(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}
