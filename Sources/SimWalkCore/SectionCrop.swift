//
// Copyright © Agulhas Labs
//

import Foundation

/// The crop of one side's screenshot that shows a flag: the bundle-relative screenshot path and a rect in it.
///
/// **Every flag names one.** A flag the reader cannot look at is a claim to be taken on trust, and the differ is a stand-in for looking at the screenshots, not a replacement for being able to.
public struct SectionCrop: Codable, Equatable, Sendable {
    /// Which bundle the screenshot is in.
    public var side: BundleDiff.Side
    /// The screenshot, relative to that bundle.
    public var screenshotPath: String
    /// The section's box in the screenshot, in the tree's points (the screenshot's pixels divided by the device's scale).
    public var rect: AXNode.Frame
    /// How much of the section the screenshot shows.
    public var visibility: Visibility

    public init(side: BundleDiff.Side, screenshotPath: String, rect: AXNode.Frame, visibility: Visibility) {
        self.side = side
        self.screenshotPath = screenshotPath
        self.rect = rect
        self.visibility = visibility
    }
}

public extension SectionCrop {
    /// How much of a section a screenshot shows — the tree holds content below the fold that the picture does not.
    enum Visibility: String, Codable, Sendable {
        /// All of it; `rect` is the section's frame.
        case whole
        /// Part of it; `rect` is the section's frame clipped to the screenshot.
        case clipped
        /// None of it; `rect` is the section's frame, outside the screenshot, and there is nothing to crop.
        case notInScreenshot
    }
}
