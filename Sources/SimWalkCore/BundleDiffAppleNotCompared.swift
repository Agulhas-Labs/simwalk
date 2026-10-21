//
// Copyright © Agulhas Labs
//

import Foundation

extension BundleDiff {
    /// A paired state whose Apple audits could not be compared, with why.
    struct AppleNotCompared: Equatable {
        let screenID: String
        let slug: String
        let reason: String
    }

    /// Every paired state whose Apple audits could not be compared, when either bundle has any audit record; empty when neither has, since an audit nobody asked for is not one lost.
    ///
    /// Where only one bundle was audited at all, that is every paired state.
    var appleNotCompared: [AppleNotCompared] {
        if let side = appleNotAudited {
            return screens.flatMap { screen in
                screen.states.map { AppleNotCompared(screenID: screen.id, slug: $0.slug, reason: "the \(side.rawValue) was not audited") }
            }
        }
        return screens.flatMap { screen in
            BundleDiffRendering.appleNoteGroups(of: screen).map { AppleNotCompared(screenID: screen.id, slug: $0.slug, reason: $0.reason) }
        }
    }
}
