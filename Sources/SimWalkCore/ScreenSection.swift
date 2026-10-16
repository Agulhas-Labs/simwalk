//
// Copyright © Agulhas Labs
//

import Foundation

/// One section of a captured screen, as a ``Segmenter`` cut it: what the differ pairs between two bundles and reports the form of — never the values in it.
///
/// Named `ScreenSection` rather than `Section` so that a consumer importing SwiftUI beside this module never has to qualify it.
public struct ScreenSection: Codable, Equatable, Sendable {
    /// What pairs this section with its counterpart in another capture of the screen: an identifier the app set, else the shape of its heading (``TextShape``), else `untitled` — never a raw figure or date, and suffixed ` #2`, ` #3` where a screen repeats one.
    public var key: String
    /// Whether this is content or one of the bars the system draws around it.
    public var role: Role
    /// The box its elements span, in the capture's coordinate space.
    public var frame: AXNode.Frame
    /// Where it sits against the capture's viewport; the tree includes content below the fold that the screenshot does not show.
    public var placement: Placement
    /// Every run of text in it, in tree order, by shape and frame.
    public var textRuns: [TextRun]
    /// The box its members span that the layout sets rather than their text — a cell, a row or a card that reaches past what it says, or an element with no text in it; `nil` where every member hugs its text, so that the section's edges are wherever its words end.
    public var containerFrame: AXNode.Frame?

    public init(key: String, role: Role, frame: AXNode.Frame, placement: Placement, textRuns: [TextRun], containerFrame: AXNode.Frame? = nil) {
        self.key = key
        self.role = role
        self.frame = frame
        self.placement = placement
        self.textRuns = textRuns
        self.containerFrame = containerFrame
    }
}

public extension ScreenSection {
    /// What a section is on the screen.
    ///
    /// **Bars are kept as sections of their own, marked**, rather than dropped: a tab bar that goes missing, or content drawn under one, is a finding about form, and the overlap rule needs the bar's box to make it. The differ compares content sections for order and bars for presence and box alone.
    enum Role: String, Codable, Sendable {
        case content
        case navigationBar
        case tabBar
        case toolbar
    }

    /// A section's frame against the capture's viewport, the root element's frame.
    enum Placement: String, Codable, Sendable {
        case onScreen
        case partlyOffScreen
        case offScreen
    }

    /// One run of text: its shape, which a figure or a date does not change, and where it is drawn.
    struct TextRun: Codable, Equatable, Sendable {
        /// The text with every number written `{n}` (``TextShape``).
        public var shape: String
        /// Where the run is drawn.
        public var frame: AXNode.Frame

        public init(shape: String, frame: AXNode.Frame) {
            self.shape = shape
            self.frame = frame
        }
    }
}
