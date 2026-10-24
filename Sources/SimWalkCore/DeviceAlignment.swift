//
// Copyright © Agulhas Labs
//

import Foundation

/// Whether the device must be turned to match an app that drew landscape on a device held portrait (SimWalk#222).
///
/// **An iPad app that supports landscape only launches landscape while the device stays portrait**, and a screen-point step (`tapPoint`, a `drag` without a label) is mapped through the device's orientation, not the app's frame: the same point then lands in the portrait grid, while the answer says it landed in the app's landscape frame. The turn is always to `.landscapeLeft`, and the re-check shows only that the frame stayed wide, so it does not prove the points land unrotated for an app locked to the other landscape side. An iPhone turns itself for such an app (SimWalk#149), so this is an iPad's case in practice. The runner therefore aligns the device to the app after every launch, and hands the orientation back as it does a state's.
///
/// The decision is the app's root frame (``OrientationCheck/judged(_:)``) against the device: a frame wider than tall on a device not landscape. **A state that names an orientation is never aligned** — `portrait` is held to the app by ``OrientationCheck/refusal(stated:frame:)``, and `landscape` is already turned to.
public struct DeviceAlignment {
    /// Whether the device is to be turned to landscape: the state names no orientation, the app's `frame` is landscape and the device is not.
    public static func turnsToLandscape(stated: Walkbook.Orientation?, frame: AXNode.Frame, deviceIsLandscape: Bool) -> Bool {
        stated == nil && !deviceIsLandscape && OrientationCheck.judged(frame) == .landscape
    }

    /// The line an answer carries when the device was turned to match the app; a walk's names the states it was turned for.
    public static func note(states: [String] = []) -> String {
        note(label: "states", names: states)
    }

    /// The same line for a dry run, which turns the device per screen and names the screens.
    public static func note(screens: [String]) -> String {
        note(label: "screen ids", names: screens)
    }

    private static func note(label: String, names: [String]) -> String {
        let named = names.isEmpty ? "" : " (\(label): \(names.joined(separator: ", ")))"
        return "device turned: the app drew landscape on a device held portrait, so the device was turned to landscape-left to match\(named) (SimWalk#222)"
    }
}
