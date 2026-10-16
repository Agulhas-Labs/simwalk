//
// Copyright © Agulhas Labs
//

import Foundation

/// A row that draws a trailing disclosure glyph — the chevron that tells a user "this opens something".
///
/// Found by shape rather than by name, because the glyph is a rendered symbol and carries no label, identifier or type of its own: in a real capture it is an unlabelled `Other` of about 7.7 × 13.7 points, sitting hard against its row's trailing edge. Nothing about it says "chevron" to a machine except where it is and how big it is, so that is what this matches on.
public struct DisclosureRow: Equatable, Sendable {
    /// The screen this row was captured on.
    public let screenID: String
    /// The capture state's slug, so a finding in one theme but not another is nameable.
    public let stateSlug: String
    /// The row element's accessibility type, as XCUITest named it.
    public let type: String
    /// The row's accessibility label — what a reader recognises it by.
    public let label: String
    /// Where the row sits, for the crop a reader would open.
    public let frame: AXNode.Frame

    public init(screenID: String, stateSlug: String, type: String, label: String, frame: AXNode.Frame) {
        self.screenID = screenID
        self.stateSlug = stateSlug
        self.type = type
        self.label = label
        self.frame = frame
    }

    /// Whether this row is typed as something a user can operate.
    ///
    /// A row that draws a chevron and is not one of these is reachable by sight and not by VoiceOver, Full Keyboard Access, Switch Control, or any test that queries for controls.
    public var isControl: Bool {
        Self.controlTypes.contains(type)
    }

    /// The XCUITest element types that are operable.
    ///
    /// Deliberately a small list of the ones that can carry a disclosure row, not every operable type XCUITest defines — a `Slider` typed row is not the mistake this looks for, and a longer list only makes the check quieter.
    static let controlTypes: Set<String> = [
        "Button", "Link", "Cell", "MenuItem", "Switch", "PopUpButton", "DisclosureTriangle",
    ]
}
