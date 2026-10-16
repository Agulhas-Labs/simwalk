//
// Copyright © Agulhas Labs
//

import Foundation

/// One capture as the form rules read it: its sections, the viewport they were placed against, and the screenshot a crop of them is taken from.
public struct SegmentedCapture: Equatable, Sendable {
    /// The capture's screenshot, as a path relative to its bundle.
    public var screenshotPath: String
    /// The root element's frame — the extent of the screenshot, in the tree's points.
    public var viewport: AXNode.Frame
    /// The capture's sections, in the segmenter's reading order.
    public var sections: [ScreenSection]
    /// Whether the walk reached this screen by a `scrollTo`, so where its first section sits depends on how far the walk scrolled — on how many rows sit above the target — rather than on the layout.
    public var scrolled: Bool

    public init(screenshotPath: String, viewport: AXNode.Frame, sections: [ScreenSection], scrolled: Bool = false) {
        self.screenshotPath = screenshotPath
        self.viewport = viewport
        self.sections = sections
        self.scrolled = scrolled
    }

    /// `tree` cut into sections by `segmenter`, placed against the tree's own root frame.
    public init(tree: AXNode, screenshotPath: String, segmenter: any Segmenter, scrolled: Bool = false) {
        self.init(screenshotPath: screenshotPath, viewport: tree.frame, sections: segmenter.sections(of: tree), scrolled: scrolled)
    }

    /// The content sections, in order — the bars left out.
    public var contentSections: [ScreenSection] {
        sections.filter { $0.role == .content }
    }

    /// The section with `key`, when this capture has one.
    public func section(keyed key: String) -> ScreenSection? {
        sections.first { $0.key == key }
    }

    /// The content section drawn directly before `section`; `nil` for the first, and for a bar.
    public func contentSection(before section: ScreenSection) -> ScreenSection? {
        let content = contentSections
        guard let index = content.firstIndex(where: { $0.key == section.key }), index > 0 else { return nil }
        return content[index - 1]
    }

    /// The crop of this capture's screenshot that shows `section`.
    ///
    /// The rect is in the tree's points, the screenshot's own coordinate space at the device's scale: the section's frame clipped to the viewport when it runs past an edge, and the frame itself, marked ``SectionCrop/Visibility/notInScreenshot``, when none of it is drawn — the section is in the tree but below (or above) the picture, so a crop of it would show nothing.
    public func crop(of section: ScreenSection, side: BundleDiff.Side) -> SectionCrop {
        switch section.placement {
        case .onScreen:
            SectionCrop(side: side, screenshotPath: screenshotPath, rect: section.frame, visibility: .whole)
        case .partlyOffScreen:
            SectionCrop(side: side, screenshotPath: screenshotPath, rect: Self.intersection(section.frame, viewport), visibility: .clipped)
        case .offScreen:
            SectionCrop(side: side, screenshotPath: screenshotPath, rect: section.frame, visibility: .notInScreenshot)
        }
    }

    /// The part of `frame` inside `viewport`; empty-sized at the nearer edge when they do not meet.
    static func intersection(_ frame: AXNode.Frame, _ viewport: AXNode.Frame) -> AXNode.Frame {
        let minX = max(frame.x, viewport.x)
        let minY = max(frame.y, viewport.y)
        let maxX = min(frame.x + frame.width, viewport.x + viewport.width)
        let maxY = min(frame.maxY, viewport.maxY)
        return AXNode.Frame(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }
}
