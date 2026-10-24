//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// The device is turned to an app that drew landscape on a device held portrait (SimWalk#222).
struct DeviceAlignmentTests {
    private static let landscape = AXNode.Frame(x: 0, y: 0, width: 1133, height: 744)
    private static let portrait = AXNode.Frame(x: 0, y: 0, width: 744, height: 1133)

    /// The measured case: an iPad mini's landscape-only app, device portrait, no orientation named.
    @Test
    func aLandscapeAppOnAPortraitDeviceTurnsTheDevice() {
        #expect(DeviceAlignment.turnsToLandscape(stated: nil, frame: Self.landscape, deviceIsLandscape: false))
    }

    /// Nothing to do when the device already agrees, or the app is portrait.
    @Test
    func aDeviceThatAgreesIsLeftAlone() {
        #expect(!DeviceAlignment.turnsToLandscape(stated: nil, frame: Self.landscape, deviceIsLandscape: true))
        #expect(!DeviceAlignment.turnsToLandscape(stated: nil, frame: Self.portrait, deviceIsLandscape: false))
        #expect(!DeviceAlignment.turnsToLandscape(stated: nil, frame: Self.portrait, deviceIsLandscape: true))
    }

    /// A state that names an orientation is never aligned: `portrait` is the existing refusal's, `landscape` is already turned to.
    @Test
    func aStateNamingAnOrientationIsNeverAligned() {
        #expect(!DeviceAlignment.turnsToLandscape(stated: .portrait, frame: Self.landscape, deviceIsLandscape: false))
        #expect(!DeviceAlignment.turnsToLandscape(stated: .landscape, frame: Self.landscape, deviceIsLandscape: false))
    }

    /// A square or empty frame cannot be judged, so it turns nothing.
    @Test
    func aFrameThatCannotBeJudgedTurnsNothing() {
        #expect(!DeviceAlignment.turnsToLandscape(stated: nil, frame: AXNode.Frame(x: 0, y: 0, width: 800, height: 800), deviceIsLandscape: false))
        #expect(!DeviceAlignment.turnsToLandscape(stated: nil, frame: AXNode.Frame(x: 0, y: 0, width: 0, height: 0), deviceIsLandscape: false))
    }

    /// The answer's line names the issue and, for a walk, the states.
    @Test
    func theNoteNamesTheIssueAndTheStates() {
        #expect(DeviceAlignment.note().contains("SimWalk#222"))
        #expect(DeviceAlignment.note(states: ["home [light]"]).contains("(states: home [light])"))
    }

    /// The note says what was done and claims nothing about where points land, which the re-check cannot show.
    @Test
    func theNoteStatesTheTurnAndClaimsNothingAboutPoints() {
        #expect(DeviceAlignment.note().contains("landscape-left"))
        #expect(!DeviceAlignment.note().contains("screen-point"))
    }
}
