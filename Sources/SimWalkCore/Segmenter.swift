//
// Copyright © Agulhas Labs
//

import Foundation

/// Cuts one captured screen into the sections the structural differ compares, pairing a run's section with a reference's by ``ScreenSection/key``.
///
/// **The plug-in point for a design system's own boundaries** (Brief §2.2, §7.2). ``AXSegmenter`` reads the accessibility tree alone, which is what any app offers; a design system that draws hairlines or card backgrounds the tree does not carry segments more exactly by conforming here, and the differ's form rules read the sections the same way from either.
public protocol Segmenter {
    /// `tree`'s sections, in reading order: navigation bars, the content, then toolbars and tab bars.
    func sections(of tree: AXNode) -> [ScreenSection]
}
