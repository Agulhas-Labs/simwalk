//
// Copyright © Agulhas Labs
//

@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// A spinner holds still, so the settle window rewards it: an app's Browse tab captured as a bare spinner with an empty tree, filed `captured` with `axTreeSettled: true` (SimWalk#7).
///
/// The answer is a content check rather than a longer timer, because no threshold separates a loading tree from a still one — a loading tree is the *more* still of the two, on any machine.
struct ScreenContentCheckTests {
    /// The real specimen, in shape: an app name, a tab bar, and an unlabelled spinner.
    ///
    /// Nothing on it belongs to the screen it was filed under.
    @Test
    func aspinnerInsideAtabBarHoldsNoScreen() {
        #expect(ScreenContentCheck.isChromeOnly(CaptureBundleFixture.loadingScreen()))
        #expect(ScreenContentCheck.contentLabels(in: CaptureBundleFixture.loadingScreen()).isEmpty)
    }

    /// The same tab a second later, with the same chrome around it — so what separates the two is the content and not the frame.
    @Test
    func thesameTabPopulatedHoldsItsOwnLabels() {
        #expect(!ScreenContentCheck.isChromeOnly(CaptureBundleFixture.populatedScreen()))
        #expect(ScreenContentCheck.contentLabels(in: CaptureBundleFixture.populatedScreen()) == ["Heart"])
    }

    /// The tab bar's own buttons are chrome: they are on the loading state and the loaded one alike, so counting them would make the check vacuous on the very specimen it was built from.
    @Test
    func thetabBarsButtonsAreNotTheScreensContent() {
        let barOnly = AXNode(
            type: "Application",
            frame: Self.screenFrame,
            label: "RouteFixture",
            children: [CaptureBundleFixture.tabBar()]
        )

        #expect(ScreenContentCheck.isChromeOnly(barOnly))
    }

    /// The application's own name sits at the top of every tree this tool has ever taken, loading or loaded.
    @Test
    func theApplicationsOwnNameIsNotTheScreensContent() {
        let named = AXNode(type: "Application", frame: Self.screenFrame, label: "RouteFixture")

        #expect(ScreenContentCheck.isChromeOnly(named))
    }

    /// A pushed screen shows its navigation title before it has anything under it, so a title alone is a screen that has not arrived.
    @Test
    func anavigationTitleAloneIsAscreenThatHasNotArrived() {
        let titleOnly = AXNode(
            type: "Application",
            frame: Self.screenFrame,
            label: "RouteFixture",
            children: [
                AXNode(type: "NavigationBar", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 96), label: "Heart"),
            ]
        )

        #expect(ScreenContentCheck.isChromeOnly(titleOnly))
    }

    /// A value is not content: the spinner in the specimen carries one, so a check counting values would read the loading indicator as the thing it exists to notice was missing.
    @Test
    func avalueWithoutAlabelIsNotContent() {
        let spinnerOnly = AXNode(
            type: "Application",
            frame: Self.screenFrame,
            children: [AXNode(type: "Type36", frame: AXNode.Frame(x: 191, y: 421, width: 20, height: 20), value: "1")]
        )

        #expect(ScreenContentCheck.isChromeOnly(spinnerOnly))
    }

    private static let screenFrame = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)
}
