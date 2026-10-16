//
// Copyright © Agulhas Labs
//

@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// `ScreenIdentifier` is the public answer to "which screen is this" — `bundle screen` prints it and walkbook `expect:` compares against it — so it must name the screen, never the chrome around it, a control on it, or a framework's region.
///
/// Every tree here is shaped like a real capture (`ScreenTreeFixture`): the navigation bar ahead of the content, system-identified images inside it, a tab bar with no identifier of its own after it (SimWalk#20 round 3, finding 1).
struct ScreenIdentifierTests {
    /// The workout-detail shape: an untitled stack's bar carries SwiftUI's hosting class name and comes first in tree order; the app's own identifier is on the scroll view two nodes later, and wins.
    @Test
    func thecontentsIdentifierWinsOverAnUntitledBarAheadOfIt() {
        let tree = ScreenTreeFixture.app(
            bar: ScreenTreeFixture.navigationBar(identifier: ScreenTreeFixture.hostingClassName, back: "Entries"),
            content: ScreenTreeFixture.content(identifier: "RecordScreen.Identifiers_screen", texts: ["Evening ride", "12.4 km"])
        )

        #expect(ScreenIdentifier(of: tree) == ScreenIdentifier(value: "RecordScreen.Identifiers_screen", source: .content))
        #expect(tree.screenIdentifier == "RecordScreen.Identifiers_screen")
    }

    /// The sleep-detail shape: a titled bar — its identifier the localised title, with a trailing button mirrored by a symbol-identified `Other` — comes first, and the content's own identifier still wins.
    @Test
    func thecontentsIdentifierWinsOverATitledBarAheadOfIt() {
        let tree = ScreenTreeFixture.app(
            bar: ScreenTreeFixture.navigationBar(identifier: "Rest", back: "Overview", trailing: "Share"),
            content: ScreenTreeFixture.content(identifier: "RestScreen.Identifiers_screen", texts: ["Time asleep", "7h 02m"])
        )

        #expect(ScreenIdentifier(of: tree) == ScreenIdentifier(value: "RestScreen.Identifiers_screen", source: .content))
    }

    /// The same titled screen from an app that identifies nothing itself: the bar's title is the fallback when one is asked for, and says it came from the bar — and without the asking there is no identifier, because a title is localised and no identity for `expect:` (SimWalk#20 round 4, finding 5; this test asserted the fallback unasked until then).
    @Test
    func abarsTitleIsTheFallbackOnlyWhenAskedForAndSaysSo() {
        let tree = ScreenTreeFixture.app(
            bar: ScreenTreeFixture.navigationBar(identifier: "Rest", back: "Overview", trailing: "Share"),
            content: ScreenTreeFixture.content(identifier: nil, texts: ["Time asleep", "7h 02m"])
        )

        #expect(ScreenIdentifier(of: tree, fallingBackToUnstable: true) == ScreenIdentifier(value: "Rest", source: .navigationBar))
        #expect(ScreenIdentifier(of: tree) == nil)
        #expect(tree.screenIdentifier == nil)
    }

    /// An untitled screen from an app that identifies nothing: the only identifiers left are the hosting class, the back button's, the dimming overlay's, a chevron's and the tab items' images — and none of them names the screen, so the answer is none.
    @Test
    func noidentifierIsTheAnswerWhenOnlyChromeImagesAndFrameworkClassesCarryOne() {
        let tree = ScreenTreeFixture.app(
            bar: ScreenTreeFixture.navigationBar(identifier: ScreenTreeFixture.hostingClassName, back: "Entries"),
            content: ScreenTreeFixture.content(identifier: nil, texts: ["Evening ride"])
        )

        #expect(ScreenIdentifier(of: tree, fallingBackToUnstable: true) == nil)
    }

    /// A tab-root screen from an app that identifies nothing — no bar, the system's images, a toolbar carrying the literal `Toolbar` after the content — has no identifier, rather than the dimming overlay's (which is what first-in-tree-order answered) or the toolbar's.
    @Test
    func noidentifierRatherThanAnImagesOrAToolbars() {
        let tree = ScreenTreeFixture.app(content: ScreenTreeFixture.content(identifier: nil, texts: ["Settings"]), overlays: [ScreenTreeFixture.toolbar()])

        #expect(ScreenIdentifier(of: tree) == nil)
    }

    /// A control's identifier names that control, not the screen it sits on: an app that identifies only its buttons has no screen identifier.
    @Test
    func acontrolsOwnIdentifierIsNeverTheScreens() {
        let content = AXNode(
            type: "Other",
            frame: ScreenTreeFixture.screenFrame,
            children: [
                AXNode(type: "Button", frame: AXNode.Frame(x: 22, y: 200, width: 358, height: 44), label: "Save", identifier: "saveButton"),
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 260, width: 358, height: 16), label: "Draft", identifier: "draftLabel"),
                AXNode(type: "Cell", frame: AXNode.Frame(x: 0, y: 300, width: 402, height: 44), label: "Row", identifier: "row-1"),
            ]
        )

        #expect(ScreenIdentifier(of: ScreenTreeFixture.app(content: content)) == nil)
    }

    /// Only a container's identifier names a screen, so a node of any other type — an element, a control the runner now names, or the raw `TypeNN` an older runner wrote for one it did not — never answers, and neither does an identified container inside it: a segmented control identified `RangePicker` on a screen whose container carries nothing gave `RangePicker`, and a context menu gave its item's `copy` (SimWalk#20 round 4, finding 1).
    @Test(arguments: [
        "Button", "StaticText", "Image", "Cell", "TextField", "Switch", "Key", "Type20", "SegmentedControl", "Type37", "SearchField", "Type45",
        "PageIndicator", "Type34", "Picker", "PickerWheel", "DatePicker", "Stepper", "ProgressIndicator", "ActivityIndicator", "Menu", "MenuItem",
        "Type54", "WebView", "Map", "Type99",
    ])
    func anidentifierOnAnythingButAContainerIsNeverTheScreens(type: String) {
        let control = AXNode(
            type: type,
            frame: AXNode.Frame(x: 22, y: 200, width: 358, height: 32),
            label: "Range",
            identifier: "RangePicker",
            children: [
                AXNode(type: "Other", frame: AXNode.Frame(x: 22, y: 200, width: 179, height: 32), identifier: "RangePicker.week", children: [
                    AXNode(type: "Button", frame: AXNode.Frame(x: 22, y: 200, width: 179, height: 32), label: "Week"),
                ]),
            ]
        )
        let tree = ScreenTreeFixture.app(content: AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame, children: [
            control, ScreenTreeFixture.content(identifier: nil, texts: ["Entries"]),
        ]))

        #expect(ScreenIdentifier(of: tree, fallingBackToUnstable: true) == nil)
    }

    /// Every container type's own identifier names the screen — the allow-list is the whole rule, so each type on it is pinned.
    @Test(arguments: ["Other", "Group", "LayoutArea", "ScrollView", "Table", "CollectionView"])
    func acontainersOwnIdentifierAnswers(type: String) {
        let container = AXNode(type: type, frame: ScreenTreeFixture.screenFrame, identifier: "App.ListScreen", children: [
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 132, width: 300, height: 16), label: "Entries"),
        ])
        let tree = ScreenTreeFixture.app(content: AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame, children: [container]))

        #expect(ScreenIdentifier(of: tree) == ScreenIdentifier(value: "App.ListScreen", source: .content))
    }

    /// The app's window is a container too: an identifier the app sets on the window itself answers.
    @Test
    func thewindowsOwnIdentifierAnswers() {
        let tree = AXNode(type: "Application", frame: ScreenTreeFixture.screenFrame, label: "Example", children: [
            AXNode(type: "Window", frame: ScreenTreeFixture.screenFrame, identifier: "App.MainWindow", children: [ScreenTreeFixture.content(identifier: nil, texts: ["Entries"])]),
        ])

        #expect(tree.screenIdentifier == "App.MainWindow")
    }

    /// The tab bar's whole subtree is skipped, not merely its own identifier: a tab bar whose item wrapper carries one — a container, so a rule on the wrapper's own type would not catch it — still never answers "which screen", because it is the same on every screen.
    @Test
    func atabBarsWholeSubtreeIsSkippedNotOnlyItsOwnIdentifier() {
        var tabBar = ScreenTreeFixture.tabBar()
        tabBar.children[0].identifier = "TabItems"
        let tree = AXNode(
            type: "Application",
            frame: ScreenTreeFixture.screenFrame,
            children: [
                AXNode(type: "Window", frame: ScreenTreeFixture.screenFrame, children: [tabBar, ScreenTreeFixture.content(identifier: nil, texts: ["Home"])]),
            ]
        )

        #expect(ScreenIdentifier(of: tree) == nil)
    }

    /// A navigation bar carrying the hosting class is not a fallback either — the mangled-name rule holds on the bar step too.
    @Test
    func theFallbackRefusesAMangledBarIdentifierAsWell() {
        let tree = ScreenTreeFixture.app(
            bar: ScreenTreeFixture.navigationBar(identifier: "_TtC7Example14HostController", back: "Back"),
            content: ScreenTreeFixture.content(identifier: nil, texts: ["Body"])
        )

        #expect(ScreenIdentifier(of: tree, fallingBackToUnstable: true) == nil)
    }

    /// An identifier a framework set is refused wherever it sits — a Swift-mangled class name, an underscore-private one, and the named system regions — and reported as refused, and the search goes on inside that container, so the app's own below it still answers.
    @Test(arguments: ["_TtC7Example14HostController", "_UIDropShadowView", "PopoverDismissRegion", "inputView", "SystemInputAssistantView", "CenterPageView"])
    func aframeworksIdentifierIsRefusedAndTheSearchGoesOnInside(identifier: String) {
        let unidentified = ScreenTreeFixture.app(content: AXNode(
            type: "Other",
            frame: ScreenTreeFixture.screenFrame,
            identifier: identifier,
            children: [ScreenTreeFixture.content(identifier: nil, texts: ["Entries"])]
        ))
        let identified = ScreenTreeFixture.app(content: AXNode(
            type: "Other",
            frame: ScreenTreeFixture.screenFrame,
            identifier: identifier,
            children: [ScreenTreeFixture.content(identifier: "App.ListScreen", texts: ["Entries"])]
        ))

        #expect(ScreenIdentifier(of: unidentified) == nil)
        #expect(ScreenIdentifier.reading(unidentified, fallingBackToUnstable: true).refused == [identifier])
        #expect(ScreenIdentifier(of: identified) == ScreenIdentifier(value: "App.ListScreen", source: .content))
    }

    /// An app's identifier that happens to begin like a UIKit class — `UIKitBridgeScreen`, `UIHome` — is the app's, and answers: only an underscore-private `_UI…` is refused (SimWalk#20 round 4, finding 6; a `UI[A-Z]` prefix was refused until then).
    @Test(arguments: ["UIKitBridgeScreen", "UIHome"])
    func anappIdentifierBeginningWithUIAnswers(identifier: String) {
        let tree = ScreenTreeFixture.app(content: ScreenTreeFixture.content(identifier: identifier, texts: ["Entries"]))

        #expect(tree.screenIdentifier == identifier)
    }

    /// An app's marker on an empty container — `screen.home` on a 1 × 1 `Other` ahead of the content — is the app's own identifier and answers: a childless `Other` was refused as a region until SimWalk#20 round 4 (finding 6), and the real regions that rule caught are in the named list.
    @Test
    func anappsMarkerOnAChildlessOtherAnswers() {
        let marker = AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 0, width: 1, height: 1), identifier: "screen.home")
        let tree = ScreenTreeFixture.app(content: AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame, children: [
            marker, ScreenTreeFixture.content(identifier: nil, texts: ["Home"]),
        ]))

        #expect(tree.screenIdentifier == "screen.home")
    }

    /// A bundle written before the runner named every type holds a popover, the keyboard and a search field by their raw codes, and those read as the types they stand for; any other raw code stays itself, which is no container.
    @Test
    func araw18And19And45ReadAsTheTypesTheyStandFor() {
        #expect(ScreenIdentifier.canonicalType("Type18") == "Popover")
        #expect(ScreenIdentifier.canonicalType("Type19") == "Keyboard")
        #expect(ScreenIdentifier.canonicalType("Type45") == "SearchField")
        #expect(ScreenIdentifier.canonicalType("Type37") == "Type37")
        #expect(ScreenIdentifier.canonicalType("Other") == "Other")
    }

    /// The real shapes present nothing: the content after a bar covers the whole screen and holds text, but carries no presentation type, so it is never read as a layer presented over anything.
    @Test
    func aRealShapedScreenIsNotReadAsAPresentation() {
        let tree = ScreenTreeFixture.app(
            bar: ScreenTreeFixture.navigationBar(identifier: "Rest", back: "Overview", trailing: "Share"),
            content: ScreenTreeFixture.content(identifier: "RestScreen.Identifiers_screen", texts: ["Time asleep"]),
            overlays: [ScreenTreeFixture.toolbar()]
        )

        #expect(ScreenIdentifier.presentation(in: tree) == nil)
        #expect(ScreenIdentifier(of: tree)?.isPresented == false)
    }

    /// A page sheet over a screen still in the tree: the sheet's own identifier wins over the covered screen's, even though the covered screen's comes first in tree order — the false pass `expect:` would otherwise give on the screen underneath.
    @Test
    func apresentedSheetsIdentifierWinsOverTheCoveredScreens() {
        let tree = ScreenTreeFixture.app(
            content: ScreenTreeFixture.content(identifier: "ListScreen.Identifiers_screen", texts: ["Entries"]),
            presented: [PresentationTreeFixture.pageSheet(bar: nil, content: ScreenTreeFixture.content(identifier: "EditorScreen.Identifiers_screen", texts: ["New entry"]))]
        )

        #expect(ScreenIdentifier(of: tree) == ScreenIdentifier(value: "EditorScreen.Identifiers_screen", source: .content, isPresented: true))
    }

    /// A page sheet whose content carries nothing falls back to its own navigation bar when a fallback is asked for — never to the covered screen's content.
    @Test
    func apresentedSheetFallsBackToItsOwnBarNotToTheCoveredScreen() {
        let tree = ScreenTreeFixture.app(
            content: ScreenTreeFixture.content(identifier: "ListScreen.Identifiers_screen", texts: ["Entries"]),
            presented: [PresentationTreeFixture.pageSheet(
                bar: ScreenTreeFixture.navigationBar(identifier: "New Entry", back: "Cancel"),
                content: ScreenTreeFixture.content(identifier: nil, texts: ["Title"])
            )]
        )

        #expect(ScreenIdentifier(of: tree, fallingBackToUnstable: true) == ScreenIdentifier(value: "New Entry", source: .navigationBar, isPresented: true))
        #expect(ScreenIdentifier(of: tree) == nil)
    }

    /// An alert with no identifier of its own over an identified screen is *no identifier*, not the screen's: the screen is covered, and answering with its name is the false pass the rule exists to stop.
    @Test
    func anunidentifiedAlertOverAnIdentifiedScreenIsNoIdentifier() {
        let tree = ScreenTreeFixture.app(
            content: ScreenTreeFixture.content(identifier: "ListScreen.Identifiers_screen", texts: ["Entries"]),
            presented: [ScreenTreeFixture.alert(title: "Delete entry?")]
        )

        #expect(ScreenIdentifier.presentation(in: tree)?.kind == "Alert")
        #expect(ScreenIdentifier(of: tree) == nil)
    }

    /// An alert that does carry an identifier answers with it.
    @Test
    func anidentifiedAlertAnswersWithItsOwn() {
        let tree = ScreenTreeFixture.app(
            content: ScreenTreeFixture.content(identifier: "ListScreen.Identifiers_screen", texts: ["Entries"]),
            presented: [ScreenTreeFixture.alert(title: "Delete entry?", identifier: "DeleteConfirmation")]
        )

        #expect(ScreenIdentifier(of: tree) == ScreenIdentifier(value: "DeleteConfirmation", source: .content, isPresented: true))
    }
}
