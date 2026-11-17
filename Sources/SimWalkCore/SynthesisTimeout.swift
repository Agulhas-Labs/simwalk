//
// Copyright © Agulhas Labs
//

/// A gesture XCTest could not deliver: `Failed to press "…" Button for 3.5 seconds: Timed out while synthesizing event.` (SimWalk#274).
///
/// XCTest reports it as a test issue, after the app has gone idle, so it is the runner's or the device's fault, not the app's. The runner holds such an issue while a route gesture is in flight and performs the gesture once more; this is what it matches the issue by and what it refuses the step with when the second attempt times out too. The host reads the same text in a result bundle (`RunnerFailureDiagnosis.isSynthesisTimeout`) from a runner that did not hold it.
public struct SynthesisTimeout {
    /// Whether an issue's description, or a result bundle's failure text, is XCTest timing out synthesizing a gesture.
    public static func matches(_ description: String) -> Bool {
        description.contains("Timed out while synthesizing event")
    }

    /// Whether a tap or long press whose synthesis timed out is made once more: not when the screen was left or the tapped element's own traits changed, which says the press landed and only its confirmation timed out (SimWalk#274).
    public static func shouldRetry(screenLeft: Bool, tappedTraitChanged: Bool) -> Bool {
        !screenLeft && !tappedTraitChanged
    }

    /// The refusal of a step whose gesture timed out twice, naming the gesture and, when the step names one, the label it was made on.
    public static func refusal(_ gesture: Gesture, on label: String?) -> String {
        let target = label.map { " on '\($0)'" } ?? ""
        return "the runner could not synthesize the \(gesture.name)\(target) (XCTest timed out synthesizing the event twice); the app had gone idle, so this is the runner or the device, not the app — walk again"
    }
}

public extension SynthesisTimeout {
    /// The route gestures the runner retries, named as the refusal names them.
    enum Gesture: Equatable, Sendable {
        case tap
        case longPress
        case drag
        case scroll

        /// The gesture as the refusal says it.
        public var name: String {
            switch self {
            case .tap: "tap"
            case .longPress: "long press"
            case .drag: "drag"
            case .scroll: "scroll"
            }
        }
    }
}
