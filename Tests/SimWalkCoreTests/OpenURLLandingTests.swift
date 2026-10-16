//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// The arrival an `openURL` step waits for, replayed without a simulator: the tree has left the screen *and* the app is still in front.
struct OpenURLLandingTests {
    /// A deep link the app answers: in front throughout, and its tree leaves the screen on the second read.
    @Test
    func adeepLinkTheAppAnswersLandsWhenTheTreeLeaves() {
        #expect(OpenURLLanding.next(appInFront: true, leftScreen: false, pastDeadline: false) == .watch)
        #expect(OpenURLLanding.next(appInFront: true, leftScreen: true, pastDeadline: false) == .landed)
    }

    /// **Leaving the app is not arriving.**
    ///
    /// An `https` URL that is not a universal link opens Safari: the app's tree changes because it went to the background, and identity alone counted that as landed. The step waits, and at the deadline does not land, naming why.
    @Test
    func aURLThatPutsAnotherAppInFrontDoesNotLandAndSaysWhy() {
        #expect(OpenURLLanding.next(appInFront: false, leftScreen: true, pastDeadline: false) == .watch)
        #expect(OpenURLLanding.next(appInFront: false, leftScreen: true, pastDeadline: true) == .notLanded(reason: "the app was not in front after opening the URL"))
    }

    /// A URL the app is in front for and does nothing with is not landed, and has nothing more to say than the route — as for any step that never moved the screen.
    @Test
    func aURLTheAppIgnoresDoesNotLandWithNoFurtherReason() {
        #expect(OpenURLLanding.next(appInFront: true, leftScreen: false, pastDeadline: true) == .notLanded(reason: nil))
    }
}
