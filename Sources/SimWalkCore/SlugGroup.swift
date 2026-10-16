//
// Copyright © Agulhas Labs
//

import Foundation

/// Values that reduce to one slug, in the order the slugs first appear.
///
/// A slug is what a name becomes on disk, so anything sharing one shares a directory. Both collision questions the validators ask — screen ids that would file under one bundle directory, capture states that would overwrite each other — are this grouping with a different verdict on top. The order is first-appearance rather than sorted because every problem list in this module is printed in reading order.
struct SlugGroup: Equatable {
    /// The slug these values share.
    let slug: String
    /// The values that reduced to it, in the order they were given.
    let values: [String]

    /// Groups `values` by the slug each reduces to.
    static func grouping(_ values: [String], by slug: (String) -> String) -> [SlugGroup] {
        var valuesBySlug: [String: [String]] = [:]
        var order: [String] = []
        for value in values {
            let key = slug(value)
            if valuesBySlug[key] == nil {
                order.append(key)
            }
            valuesBySlug[key, default: []].append(value)
        }
        return order.map { SlugGroup(slug: $0, values: valuesBySlug[$0] ?? []) }
    }

    /// Groups values that are already slugs.
    static func grouping(_ slugs: [String]) -> [SlugGroup] {
        grouping(slugs) { $0 }
    }

    /// The groups holding more than one value — the ones that would collide on disk.
    static func colliding(_ groups: [SlugGroup]) -> [SlugGroup] {
        groups.filter { $0.values.count > 1 }
    }
}
