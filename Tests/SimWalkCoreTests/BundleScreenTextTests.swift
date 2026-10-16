//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// `bundle screen`'s text listing and the way it states its root — what counts as on screen, how elements that restate one another collapse, and what a line carries — split from `BundleScreenQueryTests`, which holds how a step, a state and a capture are resolved.
struct BundleScreenTextTests {
    /// A container whose label an inner element only repeats, at a frame the container's own encloses, collapses to the container: the settings-row shape a real screen carries far more of than an exact repeat (SimWalk#20 round 2, finding 7 — frames taken from a real Settings screen).
    @Test
    func acontainerWhoseLabelAChildOnlyRepeatsCollapsesToTheContainer() throws {
        let directory = try TemporaryDirectory()
        let screen = AXNode(
            type: "Application",
            frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
            children: [
                AXNode(
                    type: "Window",
                    frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
                    identifier: "SettingsScreen",
                    children: [
                        AXNode(
                            type: "Button",
                            frame: AXNode.Frame(x: 16, y: 589.3, width: 370, height: 78),
                            label: "General",
                            children: [
                                AXNode(type: "StaticText", frame: AXNode.Frame(x: 43.7, y: 604.3, width: 190, height: 48), label: "General"),
                            ]
                        ),
                    ]
                ),
            ]
        )
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "settings", captures: [
                CaptureBundleFixture.Capture(screenID: "settings", state: Walkbook.CaptureState(theme: .light), tree: screen),
            ]),
        ])

        let answer = try BundleScreenQuery(bundle).answer(step: "1")

        #expect(answer.text.contains(", 1 text element"))
        #expect(answer.text.contains("General · Button ·"))
        #expect(!answer.text.contains("General · StaticText ·"))
    }

    /// Accessibility order is tree order, not vertical position — a label lower on screen but earlier in the tree still comes first, the shape a scrolled screen's tree actually takes (SimWalk#20 round 2, finding 5).
    @Test
    func accessibilityOrderIsTreeOrderRatherThanVerticalPosition() throws {
        let directory = try TemporaryDirectory()
        let screen = AXNode(
            type: "Application",
            frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
            children: [
                AXNode(
                    type: "Window",
                    frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
                    identifier: "OrderScreen",
                    children: [
                        AXNode(type: "StaticText", frame: AXNode.Frame(x: 14, y: 700, width: 300, height: 24), label: "Lower on screen, first in the tree"),
                        AXNode(type: "StaticText", frame: AXNode.Frame(x: 14, y: 100, width: 300, height: 24), label: "Higher on screen, second in the tree"),
                    ]
                ),
            ]
        )
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "order", captures: [
                CaptureBundleFixture.Capture(screenID: "order", state: Walkbook.CaptureState(theme: .light), tree: screen),
            ]),
        ])

        let answer = try BundleScreenQuery(bundle).answer(step: "1")

        let first = try #require(answer.text.range(of: "Lower on screen, first in the tree"))
        let second = try #require(answer.text.range(of: "Higher on screen, second in the tree"))

        #expect(first.lowerBound < second.lowerBound)
    }

    /// An element's value joins its label instead of being dropped — a switch's state, here, which round 1 showed as its label alone with nothing to say whether it was on (SimWalk#20 round 2, finding 6).
    @Test
    func anElementsValueJoinsItsLabelRatherThanBeingDropped() throws {
        let directory = try TemporaryDirectory()
        let screen = AXNode(
            type: "Application",
            frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
            children: [
                AXNode(
                    type: "Window",
                    frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
                    identifier: "SettingsScreen",
                    children: [
                        AXNode(type: "Switch", frame: AXNode.Frame(x: 300, y: 200, width: 51, height: 31), label: "Cycle tracking", value: "0"),
                    ]
                ),
            ]
        )
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "settings", captures: [
                CaptureBundleFixture.Capture(screenID: "settings", state: Walkbook.CaptureState(theme: .light), tree: screen),
            ]),
        ])

        let answer = try BundleScreenQuery(bundle).answer(step: "1")

        #expect(answer.text.contains("Cycle tracking = 0 · Switch ·"))
    }

    /// Only text whose frame intersects the capture's own frame is on screen: a line wholly below the viewport is left out of the text and counted, one straddling the edge is kept — the "does the screen show X" answer never says yes for text the screenshot cannot hold (SimWalk#20 round 3, finding 2).
    @Test
    func textOutsideTheCapturesFrameIsOmittedAndCounted() throws {
        let answer = try Self.answer(for: [
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 120, width: 300, height: 16), label: "Top of the screen"),
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 860, width: 300, height: 30), label: "Straddling the bottom edge"),
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 874, width: 300, height: 16), label: "Starting exactly at the edge"),
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 1344, width: 300, height: 24), label: "Far below the fold"),
        ])

        #expect(answer.text.contains("2 text elements on screen; 2 off screen, omitted — --all lists them"))
        #expect(answer.text.contains("Top of the screen · StaticText"))
        #expect(answer.text.contains("Straddling the bottom edge · StaticText"))
        #expect(!answer.text.contains("Starting exactly at the edge"))
        #expect(!answer.text.contains("Far below the fold"))
    }

    /// `--match` searches the whole tree (SimWalk#101): an off-screen match is listed after the on-screen ones, marked, and counted — at large type the element an audit finding named is usually below the fold.
    @Test
    func amatchFindsAnOffScreenElementAndMarksIt() throws {
        let answer = try Self.answer(for: Self.heartTree, match: "heart")

        #expect(answer.text.contains("1 of 2 on-screen elements match 'heart', and 1 off screen (listed)"))
        #expect(answer.text.contains("Heart rate variability · StaticText"))
        #expect(answer.text.contains("Heart rate variability · StaticText · 22,1100 300×16 (off screen)"))
        let onScreen = try #require(answer.text.range(of: "Resting heart rate"))
        let offScreen = try #require(answer.text.range(of: "Heart rate variability"))
        #expect(onScreen.lowerBound < offScreen.lowerBound)
        #expect(!answer.text.contains("Steps"))
    }

    /// `--all` lists the off-screen elements after the on-screen ones, each marked; the on-screen lines carry no mark.
    @Test
    func allListsOffScreenElementsMarked() throws {
        let answer = try Self.answer(for: Self.heartTree, all: true)

        #expect(answer.text.contains("2 text elements on screen; 1 off screen (listed)"))
        #expect(answer.text.contains("Heart rate variability · StaticText"))
        #expect(answer.text.contains("(off screen)"))
        #expect(!answer.text.contains("Steps · StaticText · 22,160 300×16 (off screen)"))
    }

    /// A root that reports no frame (Settings' application node) bounds the screen by its window, so the text answer lists its elements as on screen, as `--tree` does.
    @Test
    func aRootWithNoFrameStillListsItsElementsOnScreen() throws {
        let directory = try TemporaryDirectory()
        let window = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)
        let screen = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 0, height: 0), children: [
            AXNode(type: "Window", frame: window, children: [AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 120, width: 300, height: 16), label: "Top of the screen")]),
        ])
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "settings", captures: [
                CaptureBundleFixture.Capture(screenID: "settings", state: Walkbook.CaptureState(theme: .light), tree: screen),
            ]),
        ])

        let answer = try BundleScreenQuery(bundle).answer(step: "1")

        #expect(answer.text.contains("Top of the screen · StaticText"))
        #expect(!answer.text.contains("off screen"))
    }

    /// Without `--all` the listing omits off-screen elements and names the flag that lists them.
    @Test
    func theDefaultListingOmitsOffScreenElementsAndNamesAll() throws {
        let answer = try Self.answer(for: Self.heartTree)

        #expect(answer.text.contains("1 off screen, omitted — --all lists them"))
        #expect(!answer.text.contains("Heart rate variability"))
        #expect(!answer.text.contains("(off screen)"))
    }

    private static let heartTree = [
        AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 120, width: 300, height: 16), label: "Resting heart rate"),
        AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 160, width: 300, height: 16), label: "Steps"),
        AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 1100, width: 300, height: 16), label: "Heart rate variability"),
    ]

    /// A container restating a control's label collapses to the control, not the container: the type is a fact a reader acts on, and a `Share` button printed as `Share · Other` loses it (SimWalk#20 round 3, finding 3 — the navigation-bar shape real detail screens carry).
    @Test
    func acollapseKeepsTheMoreSpecificTypeOverABareContainer() throws {
        let answer = try Self.answer(for: [
            AXNode(
                type: "Other",
                frame: AXNode.Frame(x: 346, y: 66, width: 36, height: 36),
                label: "Share",
                children: [AXNode(type: "Button", frame: AXNode.Frame(x: 350, y: 66, width: 29, height: 36), label: "Share")]
            ),
            AXNode(
                type: "Other",
                frame: AXNode.Frame(x: 308, y: 764, width: 53, height: 14),
                label: "+0.4 km",
                children: [AXNode(type: "StaticText", frame: AXNode.Frame(x: 308, y: 764, width: 53, height: 14), label: "+0.4 km")]
            ),
        ])

        #expect(answer.text.contains("Share · Button · 350,66 29×36"))
        #expect(!answer.text.contains("Share · Other"))
        #expect(answer.text.contains("+0.4 km · StaticText"))
        #expect(!answer.text.contains("+0.4 km · Other"))
        #expect(answer.text.contains("2 text elements on screen"))
    }

    /// A collapse needs the values to match as well as the labels: a same-labelled container around a slider would otherwise drop the slider's value, which is the one fact on the line a reader asked for.
    @Test
    func acontainerAndAControlWhoseValuesDifferAreBothKept() throws {
        let answer = try Self.answer(for: [
            AXNode(
                type: "Other",
                frame: AXNode.Frame(x: 16, y: 300, width: 370, height: 60),
                label: "Volume",
                children: [AXNode(type: "Slider", frame: AXNode.Frame(x: 100, y: 310, width: 270, height: 40), label: "Volume", value: "40%")]
            ),
        ])

        #expect(answer.text.contains("Volume · Other"))
        #expect(answer.text.contains("Volume = 40% · Slider"))
    }

    /// A same-labelled descendant outside its ancestor's frame is its own element, not a restatement: the collapse is a frame test as well as a text one.
    @Test
    func asameLabelledDescendantOutsideItsAncestorsFrameIsKept() throws {
        let answer = try Self.answer(for: [
            AXNode(
                type: "Button",
                frame: AXNode.Frame(x: 16, y: 200, width: 370, height: 44),
                label: "General",
                children: [AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 400, width: 200, height: 20), label: "General")]
            ),
        ])

        #expect(answer.text.contains("General · Button"))
        #expect(answer.text.contains("General · StaticText"))
    }

    /// Two otherwise-identical siblings whose values differ are two elements, not an exact repeat.
    @Test
    func anexactRepeatNeedsTheSameValueToo() throws {
        let frame = AXNode.Frame(x: 300, y: 200, width: 51, height: 31)
        let answer = try Self.answer(for: [
            AXNode(type: "Switch", frame: frame, label: "Alerts", value: "0"),
            AXNode(type: "Switch", frame: frame, label: "Alerts", value: "1"),
        ])

        #expect(answer.text.contains("Alerts = 0 · Switch"))
        #expect(answer.text.contains("Alerts = 1 · Switch"))
    }

    /// An element with a value and no label — a text field holding what was typed — is listed rather than dropped; one whose value only restates a labelled ancestor's (the unlabelled switch inside a labelled one, as real captures carry) adds nothing and is not.
    @Test
    func anunlabelledValueIsListedUnlessAnAncestorAlreadyCarriesIt() throws {
        let answer = try Self.answer(for: [
            AXNode(type: "TextField", frame: AXNode.Frame(x: 22, y: 120, width: 358, height: 44), value: "Morning walk"),
            AXNode(
                type: "Switch",
                frame: AXNode.Frame(x: 319, y: 334, width: 61, height: 28),
                label: "Reminders",
                value: "0",
                children: [AXNode(type: "Switch", frame: AXNode.Frame(x: 319, y: 334, width: 63, height: 28), value: "0")]
            ),
        ])

        #expect(answer.text.contains("(no label) = Morning walk · TextField"))
        #expect(answer.text.contains("Reminders = 0 · Switch"))
        #expect(answer.text.contains("2 text elements on screen"))
    }

    /// An on-screen unlabelled value is dropped only for an ancestor *on screen* carrying it: when the only one is wholly off screen, its line is off screen too, and dropping the value would leave nothing on screen to say what the screenshot shows.
    @Test
    func anonScreenValueIsKeptWhenOnlyAnOffScreenAncestorCarriesIt() throws {
        let answer = try Self.answer(for: [
            AXNode(
                type: "Other",
                frame: AXNode.Frame(x: 16, y: 900, width: 370, height: 44),
                label: "Reminders",
                value: "1",
                children: [AXNode(type: "Switch", frame: AXNode.Frame(x: 319, y: 400, width: 61, height: 28), value: "1")]
            ),
        ])

        #expect(answer.text.contains("(no label) = 1 · Switch"))
        #expect(answer.text.contains("1 text element on screen; 1 off screen, omitted"))
    }

    /// `--match` searches the value as well as the label — the line a reader was shown carries both.
    @Test
    func matchFindsTextInAValue() throws {
        let answer = try Self.answer(for: [
            AXNode(type: "Other", frame: AXNode.Frame(x: 30, y: 525, width: 342, height: 104), label: "Sleep stages chart", value: "6h 37m"),
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 30, y: 640, width: 100, height: 16), label: "Awake"),
        ], match: "37m")

        #expect(answer.text.contains("1 of 2 on-screen elements match '37m'"))
        #expect(answer.text.contains("Sleep stages chart = 6h 37m · Other"))
    }

    /// A navigation bar's title answers only when the content carries nothing, and the answer says it is the bar's title, that it is localised, and what to set instead — a title is no stable identity for `expect:`, which the answer is the one place to learn (SimWalk#20 round 4, finding 5; the wording changed from "the navigation bar's — the content carries no identifier").
    @Test
    func anavigationBarsTitleIsLabelledAsTheBarsLocalisedTitle() throws {
        let tree = ScreenTreeFixture.app(
            bar: ScreenTreeFixture.navigationBar(identifier: "Rest", back: "Overview"),
            content: ScreenTreeFixture.content(identifier: nil, texts: ["Time asleep"])
        )

        let answer = try Self.answer(tree: tree)

        #expect(answer.text.contains("root 'Rest' (the navigation bar's title — localised; set an accessibilityIdentifier for a stable expect:)"))
    }

    /// A presented page sheet's own bar title says both where it was read and that it is localised.
    @Test
    func apresentedSheetsBarTitleSaysItIsOnThePresentationAndLocalised() throws {
        let tree = ScreenTreeFixture.app(
            content: ScreenTreeFixture.content(identifier: "ListScreen.Identifiers_screen", texts: ["Entries"]),
            presented: [PresentationTreeFixture.pageSheet(
                bar: ScreenTreeFixture.navigationBar(identifier: "New Entry", back: "Cancel"),
                content: ScreenTreeFixture.content(identifier: nil, texts: ["Title"])
            )]
        )

        let answer = try Self.answer(tree: tree)

        #expect(answer.text.contains("root 'New Entry' (the navigation bar's title, on the presented page sheet — localised; set an accessibilityIdentifier for a stable expect:)"))
    }

    /// An identifier every element of one container shares is shown, labelled as no stable identity — it may be a shared row identifier — and on a presentation says so as well.
    @Test
    func apropagatedIdentifierIsLabelledAsNoStableIdentity() throws {
        let rows = AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 116, width: 402, height: 700), children: [
            AXNode(type: "Button", frame: AXNode.Frame(x: 22, y: 132, width: 358, height: 48), label: "Morning run", identifier: "workoutRow"),
            AXNode(type: "Button", frame: AXNode.Frame(x: 22, y: 184, width: 358, height: 48), label: "Swim", identifier: "workoutRow"),
        ])
        let onScreen = try Self.answer(tree: ScreenTreeFixture.app(content: AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame, children: [rows])))
        let onSheet = try Self.answer(tree: ScreenTreeFixture.application(window: [
            PresentationTreeFixture.pageSheet(bar: nil, content: AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame, children: [rows])),
        ]))

        #expect(onScreen.text.contains("root 'workoutRow' (shared by every element of one container — not a stable screen identity)"))
        #expect(onSheet.text.contains("root 'workoutRow' (shared by every element of one container, on the presented page sheet — not a stable screen identity)"))
    }

    /// When a refusal removed the only candidate, the answer names what it refused rather than saying no container carries one — which a container, carrying a framework's identifier, does (SimWalk#20 round 4, finding 6).
    @Test
    func arefusedFrameworkIdentifierIsNamedRatherThanNoContainer() throws {
        let screen = ScreenTreeFixture.app(content: AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame, identifier: "_UIHostingView", children: [
            ScreenTreeFixture.content(identifier: nil, texts: ["Entries"]),
        ]))
        let presented = ScreenTreeFixture.app(
            content: ScreenTreeFixture.content(identifier: "App.ListScreen", texts: ["Entries"]),
            presented: [AXNode(type: "Alert", frame: AXNode.Frame(x: 36, y: 340, width: 330, height: 190), identifier: "_TtC5UIKit17UIAlertController", children: [
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 56, y: 360, width: 290, height: 22), label: "Delete entry?"),
            ])]
        )

        let onScreen = try Self.answer(tree: screen)
        let onAlert = try Self.answer(tree: presented)

        #expect(onScreen.text.contains("root (no identifier — refused framework identifier '_UIHostingView')"))
        #expect(!onScreen.text.contains("no container"))
        #expect(onAlert.text.contains("root (presented, unidentified — on the presented Alert, refused framework identifier '_TtC5UIKit17UIAlertController')"))
    }

    /// An alert with no identifier over an identified screen answers "presented, unidentified", rather than the covered screen's identifier (the wording changed in SimWalk#20 round 4 from "no identifier on the presented Alert").
    @Test
    func anunidentifiedAlertOverTheScreenIsPresentedUnidentified() throws {
        let tree = ScreenTreeFixture.app(
            content: ScreenTreeFixture.content(identifier: "ListScreen.Identifiers_screen", texts: ["Entries"]),
            presented: [ScreenTreeFixture.alert(title: "Delete entry?")]
        )

        let answer = try Self.answer(tree: tree)

        #expect(answer.text.contains("root (presented, unidentified — nothing on the presented Alert carries a usable identifier)"))
        #expect(!answer.text.contains("root 'ListScreen"))
    }

    /// When only elements carry identifiers — every row's cell, here — the answer says no *container* carries one, rather than that the content carries none, which the rows make false (SimWalk#20 round 4, finding 4).
    @Test
    func identifiersOnlyOnElementsAreNotCalledNoIdentifierInTheContent() throws {
        let rows = AXNode(type: "CollectionView", frame: ScreenTreeFixture.screenFrame, children: [
            AXNode(type: "Cell", frame: AXNode.Frame(x: 0, y: 132, width: 402, height: 44), label: "Wi-Fi", identifier: "com.example.wifi"),
            AXNode(type: "Cell", frame: AXNode.Frame(x: 0, y: 176, width: 402, height: 44), label: "Bluetooth", identifier: "com.example.bluetooth"),
        ])
        let tree = ScreenTreeFixture.app(content: AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame, children: [rows]))

        let answer = try Self.answer(tree: tree)

        #expect(answer.text.contains("root (no identifier — no container in the content carries one)"))
    }

    /// Off-screen elements are set aside before anything collapses: a row straddling the bottom edge keeps its line even though its more specific same-label child sits wholly below the edge — collapsing first let the child replace the row and then dropped it as off screen, losing text the screenshot shows (SimWalk#20 round 4, finding 7).
    @Test
    func arowStraddlingTheEdgeKeepsItsLineWhenItsSameLabelChildIsBelowIt() throws {
        let answer = try Self.answer(for: [
            AXNode(
                type: "Other",
                frame: AXNode.Frame(x: 16, y: 850, width: 370, height: 80),
                label: "Privacy",
                children: [AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 880, width: 370, height: 44), label: "Privacy")]
            ),
        ])

        #expect(answer.text.contains("Privacy · Other · 16,850 370×80"))
        #expect(answer.text.contains("1 text element on screen"))
        #expect(!answer.text.contains("off screen, omitted"))
    }

    /// One screen, one light capture, `children` under an identified window — for the tests about the text listing rather than the lookup.
    private static func answer(for children: [AXNode], match: String? = nil, all: Bool = false) throws -> Answer {
        let tree = AXNode(
            type: "Application",
            frame: ScreenTreeFixture.screenFrame,
            label: "Example",
            children: [AXNode(type: "Window", frame: ScreenTreeFixture.screenFrame, identifier: "Screen", children: children)]
        )
        return try answer(tree: tree, match: match, all: all)
    }

    private static func answer(tree: AXNode, match: String? = nil, all: Bool = false) throws -> Answer {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "screen", captures: [CaptureBundleFixture.Capture(screenID: "screen", state: Walkbook.CaptureState(theme: .light), tree: tree)]),
        ])
        return try BundleScreenQuery(bundle).answer(step: "1", match: match, all: all)
    }
}
