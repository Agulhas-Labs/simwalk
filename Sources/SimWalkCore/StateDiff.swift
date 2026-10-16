//
// Copyright © Agulhas Labs
//

import Foundation

/// One state of one screen, captured on both sides and paired by its slug: what each side segmented, and the flags the rules raised.
public struct StateDiff: Codable, Equatable, Sendable {
    /// The state's slug, which paired the two captures.
    public var slug: String
    /// What the reference's capture segmented into.
    public var reference: Segmentation
    /// What the run's capture segmented into.
    public var run: Segmentation
    /// Every flag, in rule order — presence, order, box, row template, overlap, degenerate chart — and each rule's own stable order within it; empty where either side could not be segmented.
    public var flags: [FormFlag]

    public init(slug: String, reference: Segmentation, run: Segmentation, flags: [FormFlag]) {
        self.slug = slug
        self.reference = reference
        self.run = run
        self.flags = flags
    }

    /// Whether both sides were segmented, so that no flag means no difference rather than no comparison.
    public var isCompared: Bool {
        reference.unreadable == nil && run.unreadable == nil
    }
}

public extension StateDiff {
    /// What one side's capture came to: its screenshot, and how many sections its tree held — or why the tree could not be read.
    ///
    /// **A diff says what it segmented and what it could not** (the honest contract): a state whose tree failed to decode is kept and named, never dropped, since a missing state would read as a state with no differences.
    struct Segmentation: Codable, Equatable, Sendable {
        /// The capture's screenshot, relative to its bundle.
        public var screenshotPath: String
        /// The sections the tree was cut into; `0` when it could not be read.
        public var sectionCount: Int
        /// Why the tree could not be read; `nil` when it was.
        public var unreadable: String?

        public init(screenshotPath: String, sectionCount: Int, unreadable: String? = nil) {
            self.screenshotPath = screenshotPath
            self.sectionCount = sectionCount
            self.unreadable = unreadable
        }
    }
}
