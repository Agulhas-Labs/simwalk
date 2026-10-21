//
// Copyright © Agulhas Labs
//

import Foundation

/// One control `discover` saw and did not tap, with the reason — an entry of the skipped list, shaped as `bundle coverage` names an uncovered control.
public struct DiscoverSkip: Equatable, Sendable {
    /// The drafted screen it was seen on; `launch` for a tab read off the launch screen.
    public let screenID: String
    /// Its element type, as XCUITest names it (`Button`, `Switch`).
    public let type: String
    /// Its label, or its identifier where it has no label.
    public let name: String
    public let reason: Reason
    /// Where it was drawn, which orders the list visually.
    public let frame: AXNode.Frame

    public init(screenID: String, type: String, name: String, reason: Reason, frame: AXNode.Frame) {
        self.screenID = screenID
        self.type = type
        self.name = name
        self.reason = reason
        self.frame = frame
    }

    /// The entry as a line of the skipped list.
    public var line: String {
        "\(type) '\(AuditRowFormat.trim(name))': \(reason.rawValue)"
    }
}

public extension DiscoverSkip {
    /// Why a control was not tapped — a fixed vocabulary, so a reader can count them.
    enum Reason: String, Equatable, Sendable, CaseIterable {
        /// A plain button, a link, a cell without a disclosure glyph: tapping it could act rather than navigate.
        case notNavigation = "not a navigation affordance"
        /// A setting: its other side is a state, not a screen.
        case isSwitch = "switch"
        /// A field: reaching its other states needs text an author chooses.
        case textField = "text field"
        /// A button on an alert, which is never answered.
        case alertButton = "alert button"
        /// The row raised an alert when tapped, which ends its branch.
        case alertEndsBranch = "alert ends branch"
        /// Another control on the screen answers to the same label, so a `tap(label:)` route could not name this one.
        case labelNotUnique = "label not unique on this screen"
        /// The screen it sits on is at the depth bound.
        case beyondDepth = "beyond depth"
        /// The draft already holds the most screens it may.
        case beyondMaxScreens = "beyond max screens"
        /// It was tapped and the step did not land.
        case didNotLand = "tapped, did not land"
        /// It sits below the visible frame and the `scrollTo` that would bring it on screen did not land, so it was never tapped.
        case couldNotScroll = "could not scroll to"
        /// The crawl could not get back to the screen to tap it.
        case couldNotReturn = "could not return to this screen"
    }
}
