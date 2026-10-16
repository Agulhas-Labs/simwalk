//
// Copyright © Agulhas Labs
//

import Foundation

/// The two ways a set of screen ids fails to key a bundle: one id written twice, or two ids reducing to one directory.
///
/// The walkbook and the manifest both ask this question, and they have to ask it the same way — a walkbook that validates and then collides at `finalise` is the pre-flight check failing at the only job it has. They used to carry a copy of the grouping each, and the single line where the copies had drifted is exactly what let it happen: one slugged the *trimmed* id where every on-disk path slugs the raw one, so `" today"` and `"_today"` passed `simwalk validate`, ran a whole simulator pass, and were refused only after it.
enum ScreenIDCollision: Equatable {
    /// The same id appears more than once — "you wrote this twice".
    case duplicate(id: String, occurrences: Int)
    /// Different ids reduce to one slug — "these two are one directory".
    case colliding(slug: String, ids: [String])

    /// Every collision among `ids`, in the order their slugs first appear.
    ///
    /// The slug is taken from the id **as written**, because that is what the runner will file under. Trimming anywhere but a blankness check asks about a different id than the one that reaches the filesystem — which is why a caller drops blank ids before calling rather than trimming the ones it keeps.
    static func all(among ids: [String]) -> [ScreenIDCollision] {
        SlugGroup.colliding(SlugGroup.grouping(ids, by: CaptureBundleLayout.screenSlug)).map { group in
            let distinct = Set(group.values)
            guard distinct.count > 1 else {
                return .duplicate(id: group.values[0], occurrences: group.values.count)
            }
            return .colliding(slug: group.slug, ids: distinct.sorted())
        }
    }
}
