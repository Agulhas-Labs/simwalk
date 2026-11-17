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
    ///
    /// A comma separates screen ids, unless the walkbook has a screen whose id is the whole value: `a,b` is the two screens `a` and `b`, and `x,y` is the one screen `x,y` when the walkbook has it. Each part is trimmed and an empty part dropped; a part that is no screen is unknown, as is a value with no part at all (`,`), and the refusal names the part rather than the value it came from.
    public static func narrow(_ walkbook: Walkbook, to ids: [String]) throws -> Walkbook {
        let known = Set(walkbook.screens.map(\.id))
        var wanted = Set<String>()
        var unknown = Set<String>()
        for value in ids {
            let parts = known.contains(value) || !value.contains(",") ? [value] : value
                .split(separator: ",", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parts.isEmpty {
                // Only commas and blanks: it names no screen, and is refused as the value it was given.
                unknown.insert(value)
            }
            for part in parts {
                if known.contains(part) {
                    wanted.insert(part)
                } else {
                    unknown.insert(part)
                }
            }
        }
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
