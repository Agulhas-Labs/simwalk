//
// Copyright © Agulhas Labs
//

import SimWalkCore
import Testing

/// SimWalk#274: a gesture XCTest timed out synthesizing is recognised by its text, and a step whose gesture timed out twice is refused naming the runner or the device, not the app.
struct SynthesisTimeoutTests {
    /// The failure the issue reported, and the issue's description without the step's preamble, are a synthesis timeout; a launch timeout and an element that could not be found are not.
    @Test
    func theIssuesFailureIsASynthesisTimeoutAndALaunchTimeoutIsNot() {
        let failure = #"Failed to press "home-parent-gate" Button for 3.5 seconds: Timed out while synthesizing event."#

        #expect(SynthesisTimeout.matches(failure))
        #expect(SynthesisTimeout.matches("Timed out while synthesizing event"))
        #expect(!SynthesisTimeout.matches("Failed to launch com.x: Timed out attempting to launch app."))
        #expect(!SynthesisTimeout.matches(#"Failed to tap "Row" Button: No matches found for Element at index 1"#))
        #expect(!SynthesisTimeout.matches("Synthesize event"))
    }

    /// A long press refused after two timeouts names the label as the step names it and says whose fault it is.
    @Test
    func theRefusalForALongPressReadsAsSpecified() {
        let refusal = SynthesisTimeout.refusal(.longPress, on: "For grown-ups")

        #expect(refusal == "the runner could not synthesize the long press on 'For grown-ups' (XCTest timed out synthesizing the event twice); the app had gone idle, so this is the runner or the device, not the app — walk again")
    }

    /// Each gesture is named as the refusal says it, and a gesture with no label (a scroll, an unlabelled drag) names none.
    @Test
    func eachGestureIsNamedAndOneWithNoLabelNamesNone() {
        #expect(SynthesisTimeout.refusal(.tap, on: "Row").hasPrefix("the runner could not synthesize the tap on 'Row' ("))
        #expect(SynthesisTimeout.refusal(.drag, on: nil).hasPrefix("the runner could not synthesize the drag ("))
        #expect(SynthesisTimeout.refusal(.scroll, on: nil).hasPrefix("the runner could not synthesize the scroll ("))
    }

    /// A press whose timeout left the screen was delivered: pressing again would hit the new screen.
    @Test
    func aTimedOutPressThatLeftTheScreenIsDeliveredAndNotRetried() {
        #expect(!SynthesisTimeout.shouldRetry(screenLeft: true, tappedTraitChanged: false))
    }

    /// A press whose timeout changed the tapped element's own traits was delivered: pressing again would flip a toggle back.
    @Test
    func aTimedOutPressThatChangedTheTappedElementsTraitsIsDeliveredAndNotRetried() {
        #expect(!SynthesisTimeout.shouldRetry(screenLeft: false, tappedTraitChanged: true))
    }

    /// A press whose timeout changed nothing was never delivered, and is made once more.
    @Test
    func aTimedOutPressThatChangedNothingIsRetried() {
        #expect(SynthesisTimeout.shouldRetry(screenLeft: false, tappedTraitChanged: false))
    }
}
