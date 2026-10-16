//
// Copyright © Agulhas Labs
//

import SimWalkCore
import Testing

/// Which identifiers in a capture can name its screen (round 3): the exclusions `ScreenIdentifier` makes on the `bundle screen` feature, restated for `expect` — never a bar, never an element, never a mangled Swift class name.
struct ScreenIdentifierRuleTests {
    /// Of every identifier a real pushed screen carries, only the container the app identifies as the screen is left.
    ///
    /// The rest are on every screen it could be — the tab bar's symbol names, `BackButton`, `Toolbar`, SwiftUI's hosting class — or name one element of its content: an image's symbol name, a button's own identifier.
    @Test
    func onlyTheScreensOwnContainerIdentifierIsScreenLevel() {
        #expect(ScreenIdentifierRule.screenLevelIdentifiers(in: Self.pushedScreen(content: "activity-detail")) == ["activity-detail"])
    }

    @Test(arguments: ["NavigationBar", "Toolbar", "TabBar", "Image", "Button", "StaticText", "Cell", "TextField"])
    func barsAndElementsAreChrome(type: String) {
        #expect(ScreenIdentifierRule.isChrome(AXNode(type: type, frame: Self.frame)))
    }

    @Test(arguments: ["Other", "ScrollView", "Table", "CollectionView", "Window"])
    func containersAreNotChrome(type: String) {
        #expect(!ScreenIdentifierRule.isChrome(AXNode(type: type, frame: Self.frame)))
    }

    @Test
    func amangledSwiftClassNameIsNotUsable() {
        #expect(!ScreenIdentifierRule.isUsable("_TtGC7SwiftUI32NavigationStackHosting"))
        #expect(!ScreenIdentifierRule.isUsable(""))
        #expect(ScreenIdentifierRule.isUsable("activity-detail"))
    }

    /// What `ScreenIdentifier` reports: the content's own identifier first, whatever the navigation bar says.
    @Test
    func theScreenIsKnownByItsContentBeforeItsTitle() {
        #expect(ScreenIdentifierRule.screenIdentifier(of: Self.pushedScreen(content: "activity-detail")) == "activity-detail")
    }

    /// Round 4: when the content carries nothing, the screen is known by nothing — never by its navigation bar's title, which is localised and not unique.
    @Test
    func aScreenWhoseContentCarriesNothingIsKnownByNothing() {
        #expect(ScreenIdentifierRule.screenIdentifier(of: Self.pushedScreen(content: nil)) == nil)
    }

    /// The title is still readable as a title — for the hint a mismatch carries, never as a screen's identifier.
    @Test
    func theNavigationBarTitleIsReadAsATitle() {
        #expect(ScreenIdentifierRule.navigationBarTitle(of: Self.pushedScreen(content: nil, title: "Heart")) == "Heart")
    }

    /// A bar titled by SwiftUI's hosting class has no title worth naming.
    @Test
    func amangledTitleIsNoTitle() {
        #expect(ScreenIdentifierRule.navigationBarTitle(of: Self.pushedScreen(content: nil, title: "_TtGC7SwiftUI32NavigationStackHosting")) == nil)
    }

    /// Round 4: a title never carries an expectation, even on a screen whose content names nothing — the bar is chrome, its title included, and an `expect` naming one would flip under a locale state.
    @Test
    func aTitleNeverCarriesAnExpectation() {
        #expect(!ScreenIdentifierRule.carries("Activity", in: Self.pushedScreen(content: nil)))
    }

    /// But a title is not screen-level while the content names the screen itself.
    @Test
    func aTitleDoesNotCarryAnExpectationWhenTheContentNamesTheScreen() {
        #expect(!ScreenIdentifierRule.carries("Activity", in: Self.pushedScreen(content: "activity-detail")))
    }

    /// SimWalk#103: any screen-level identifier carries an expectation, the outer one and a nested one alike; `found` still reports the first.
    @Test
    func anyScreenLevelIdentifierCarriesAnExpectation() {
        let tree = AXNode(type: "Application", frame: Self.frame, children: [
            AXNode(type: "ScrollView", frame: Self.frame, identifier: "activity-detail", children: [
                AXNode(type: "Other", frame: Self.frame, identifier: "splits-section"),
            ]),
        ])

        #expect(ScreenIdentifierRule.screenLevelIdentifiers(in: tree) == ["activity-detail", "splits-section"])
        #expect(ScreenIdentifierRule.carries("activity-detail", in: tree))
        #expect(ScreenIdentifierRule.carries("splits-section", in: tree))
        #expect(!ScreenIdentifierRule.carries("missing", in: tree))
        #expect(ScreenIdentifierRule.screenIdentifier(of: tree) == "activity-detail")
    }

    /// An element-level identifier inside the content never counts, nor does one in the tab bar or navigation bar.
    @Test
    func elementsAndChromeNeverCarryAnExpectation() {
        let tree = Self.pushedScreen(content: "activity-detail")

        #expect(!ScreenIdentifierRule.carries("share-button", in: tree))
        #expect(!ScreenIdentifierRule.carries("heart.fill", in: tree))
        #expect(!ScreenIdentifierRule.carries("BackButton", in: tree))
        #expect(!ScreenIdentifierRule.carries("Toolbar", in: tree))
        #expect(!ScreenIdentifierRule.carries("Activity", in: tree))
    }

    private static let frame = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)

    /// `Application` > `Window` > the pushed screen: its navigation bar (back button inside), SwiftUI's mangled hosting container around the content, the toolbar, and the tab bar with its items' symbols.
    static func pushedScreen(content: String?, title: String = "Activity") -> AXNode {
        let bar = AXNode(type: "NavigationBar", frame: frame, identifier: title, children: [
            AXNode(type: "Button", frame: frame, label: "Back", identifier: "BackButton"),
        ])
        let body = AXNode(type: "Other", frame: frame, identifier: "_TtGC7SwiftUI32NavigationStackHosting", children: [
            AXNode(type: "ScrollView", frame: frame, identifier: content, children: [
                AXNode(type: "Image", frame: frame, identifier: "heart.fill"),
                AXNode(type: "Button", frame: frame, label: "Share", identifier: "share-button"),
                AXNode(type: "StaticText", frame: frame, label: "Rowing"),
            ]),
        ])
        let toolbar = AXNode(type: "Toolbar", frame: frame, identifier: "Toolbar")
        let tabs = AXNode(type: "TabBar", frame: frame, children: [
            AXNode(type: "Button", frame: frame, label: "You", identifier: "person.fill", children: [
                AXNode(type: "Image", frame: frame, identifier: "person.fill"),
            ]),
        ])
        return AXNode(type: "Application", frame: frame, label: "RouteFixture", children: [
            AXNode(type: "Window", frame: frame, children: [bar, body, toolbar, tabs]),
        ])
    }
}
