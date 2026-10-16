//
// Copyright © Agulhas Labs
//

import Foundation

/// One control a label rule objects to, in one capture.
public struct LabelFinding: Equatable, Sendable {
    /// The screen this control was captured on.
    public let screenID: String
    /// The capture state's slug, so a finding in one theme but not another is nameable.
    public let stateSlug: String
    /// The control's accessibility type, as XCUITest named it.
    public let type: String
    /// The label the rule is about, when it has one — a control with none is the finding of `unlabelledControl`.
    public let label: String?
    /// Where it sits, for the crop a reader would open.
    public let frame: AXNode.Frame
    /// What is particular to this finding beyond its label, when the rule has something to say — `duplicateLabel`'s count.
    public let note: String?

    public init(screenID: String, stateSlug: String, type: String, label: String?, frame: AXNode.Frame, note: String? = nil) {
        self.screenID = screenID
        self.stateSlug = stateSlug
        self.type = type
        self.label = label
        self.frame = frame
        self.note = note
    }
}
