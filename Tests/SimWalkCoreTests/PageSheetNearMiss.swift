//
// Copyright © Agulhas Labs
//

import SimWalkCore
import SimWalkTestSupport

/// The ways a layer can almost be a page sheet, each the real shape (`PresentationTreeFixture.pageSheet`) with one thing changed — the arguments `ScreenPresentationTests` checks are never read as presented.
enum PageSheetNearMiss: CaseIterable, Sendable {
    /// The sheet's container holds no grabber.
    case noGrabber
    /// The grabber is labelled something other than `Sheet Grabber`.
    case grabberLabelledOtherwise
    /// The dimming view stops at the screen's edges rather than reaching past them.
    case dimmingInsideTheScreen
    /// The grabber's container is drawn before the dimming view rather than after it.
    case grabberBeforeTheDimming

    /// The real page sheet's layer, with the one change.
    var layer: AXNode {
        var layer = PresentationTreeFixture.pageSheet(bar: nil, content: ScreenTreeFixture.content(identifier: "App.EditorScreen", texts: ["Title"]))
        switch self {
        case .noGrabber:
            layer.children[1].children.removeFirst()
        case .grabberLabelledOtherwise:
            layer.children[1].children[0].label = "Handle"
        case .dimmingInsideTheScreen:
            layer.children[0].frame = ScreenTreeFixture.screenFrame
        case .grabberBeforeTheDimming:
            layer.children.reverse()
        }
        return layer
    }
}
