//
// Copyright © Agulhas Labs
//

import Foundation

/// A screen's structure as the segmenter cuts it — what `discover` deduplicates screens by, never their values.
///
/// Each section's role and key, and the shape of every run of text in it (``TextShape``: each number written `{n}`). **Frames are left out**: a row's box changes with the length of what it says and with how far the list is scrolled, neither of which makes it another screen. Two detail screens that differ only in their figures are one form, so the second is not drafted again.
public struct DiscoverForm: Hashable, Sendable {
    /// One line per section, in the segmenter's order: role, key, then the text shapes.
    public let lines: [String]

    /// The form of `tree`, as `segmenter` sections it.
    public init(of tree: AXNode, segmenter: any Segmenter = AXSegmenter()) {
        lines = segmenter.sections(of: tree).map { section in
            ([section.role.rawValue, section.key] + section.textRuns.map(\.shape)).joined(separator: "\u{1F}")
        }
    }
}
