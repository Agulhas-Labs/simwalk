//
// Copyright © Agulhas Labs
//

import Foundation

/// What a `tab` step does once its button is bound, decided here so a test holds it (SimWalk#106, #95).
///
/// A tab that cannot be hit is refused whatever it reports as selected, because a modal over the app leaves the selection true and landing on it would prove nothing about the app being in front (#95). A hittable tab that is already selected is landed on untouched: the step means "be on this tab", and a tap could only pop that tab's stack to its root (#106). Any other is tapped.
public enum TabStepAction: Equatable, Sendable {
    case refuse(String)
    case landUntouched
    case tap

    public static func decide(label: String, hittable: Bool, selected: Bool) -> TabStepAction {
        guard hittable else { return .refuse(TabStepRefusal.notHittable(label: label)) }
        return selected ? .landUntouched : .tap
    }
}
