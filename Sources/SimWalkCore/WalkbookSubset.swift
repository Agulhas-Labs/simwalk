//
// Copyright © Agulhas Labs
//

import Foundation

/// Narrows a walkbook to named screens.
///
/// The iteration loop this exists for: a route names a control the build renamed, one screen of twelve goes UNREACHABLE, and confirming the one-line fix otherwise costs a full re-walk of the eleven that were already fine. The cost of iterating was proportional to the whole walkbook rather than to the change.
///
/// **The subset is a walkbook in its own right, not a flag on the original**, and that is the design decision worth stating. It is hashed as itself, so the bundle it produces records the plan that actually ran — a manifest naming the twelve-screen walkbook while holding three screens would be a bundle a reader could detect was odd and could not explain. The consequence, accepted deliberately: a subset bundle is *not* a substitute for the full one, and `walkbookHash` is what says so.
public struct WalkbookSubset {
    /// The walkbook containing only `ids`, in the original's order.
    ///
    /// Order comes from the walkbook rather than from the argument, because a walk is a plan and the order screens are reached in is part of it — a subset that honoured the caller's ordering would execute a route the author never wrote.
    public static func narrow(_ walkbook: Walkbook, to ids: [String]) throws -> Walkbook {
        let wanted = Set(ids)
        let unknown = ids.filter { id in !walkbook.screens.contains { $0.id == id } }
        guard unknown.isEmpty else {
            throw WalkbookSubsetError.unknownScreens(
                requested: unknown.sorted(),
                available: walkbook.screens.map(\.id)
            )
        }
        var narrowed = walkbook
        narrowed.screens = walkbook.screens.filter { wanted.contains($0.id) }
        return narrowed
    }
}
