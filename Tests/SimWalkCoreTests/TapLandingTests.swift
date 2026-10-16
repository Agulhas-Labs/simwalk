//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// A `tap` on an element already selected, such as iPad Settings' sidebar row General, lands though the screen does not change, when a navigation bar names it (SimWalk#125).
struct TapLandingTests {
    /// **A selected, hittable element whose tap changed nothing, under a bar naming it, was already there.**
    @Test
    func aSelectedHittableTitledElementThatChangesNothingLands() {
        let landing = TapLanding.decide(arrived: false, wasSelected: true, hittable: true, titled: true)

        #expect(landing == .alreadySelected)
    }

    /// **A selected, hittable element whose tap changed nothing did not land when no bar names it**: its detail may have been pushed deeper.
    @Test
    func aSelectedHittableElementWithoutItsTitleDoesNotLand() {
        let landing = TapLanding.decide(arrived: false, wasSelected: true, hittable: true, titled: false)

        #expect(landing == .notLanded)
    }

    /// **An unselected element whose tap changed nothing did not land, hittable or not.**
    @Test
    func anUnselectedElementThatChangesNothingDoesNotLand() {
        let landings = [true, false].map { TapLanding.decide(arrived: false, wasSelected: false, hittable: $0, titled: true) }

        #expect(landings == [.notLanded, .notLanded])
    }

    /// **A selected element that cannot be hit is not landed on** (#95): a modal over the app leaves the selection true.
    @Test
    func aSelectedElementThatIsNotHittableDoesNotLand() {
        let landing = TapLanding.decide(arrived: false, wasSelected: true, hittable: false, titled: true)

        #expect(landing == .notLanded)
    }

    /// **A tap after which the screen changed landed, whatever the rest.**
    @Test
    func aTapThatChangedTheScreenLandsWhateverTheRest() {
        let flags = [true, false]
        let landings = flags.flatMap { selected in
            flags.flatMap { hittable in
                flags.map { titled in TapLanding.decide(arrived: true, wasSelected: selected, hittable: hittable, titled: titled) }
            }
        }

        #expect(landings == Array(repeating: .landed, count: 8))
    }

    /// **A navigation bar whose identifier is the label names it.**
    @Test
    func aBarIdentifiedByTheLabelNamesIt() {
        let tree = Self.screen(Self.sidebar(selected: "General"), Self.bar(identifier: "General"))

        #expect(TapLanding.destinationTitled(label: "General", in: tree, tapped: Self.row("General")))
    }

    /// **A navigation bar labelled with the label names it.**
    @Test
    func aBarLabelledWithTheLabelNamesIt() {
        let tree = Self.screen(Self.sidebar(selected: "General"), Self.bar(label: "General"))

        #expect(TapLanding.destinationTitled(label: "General", in: tree, tapped: Self.row("General")))
    }

    /// **A navigation bar holding a `StaticText` with the label names it**, as iPad Settings' General detail does.
    @Test
    func aBarHoldingTheLabelAsTextNamesIt() {
        let tree = Self.screen(Self.sidebar(selected: "General"), Self.bar(title: "General"))

        #expect(TapLanding.destinationTitled(label: "General", in: tree, tapped: Self.row("General")))
    }

    /// **A detail pushed deeper is not the row's screen**: the bar says About while the sidebar's selected button is General.
    @Test
    func aDeeperPushIsNotTheRowsScreen() {
        let tree = Self.screen(Self.sidebar(selected: "General"), Self.bar(identifier: "About", title: "About"))

        #expect(!TapLanding.destinationTitled(label: "General", in: tree, tapped: Self.row("General")))
    }

    /// **A back button's text does not name the destination**: pushed from General to About, the bar's back button reads General, and that is the screen behind.
    @Test
    func aBackButtonsTextDoesNotNameIt() {
        let backText = AXNode(type: "StaticText", frame: AXNode.Frame(x: 330, y: 12, width: 60, height: 22), label: "General")
        let back = AXNode(type: "Button", frame: AXNode.Frame(x: 320, y: 0, width: 80, height: 44), label: "General", identifier: "BackButton", children: [backText])
        let bar = AXNode(type: "NavigationBar", frame: AXNode.Frame(x: 320, y: 0, width: 712, height: 50), identifier: "About", children: [back])
        let tree = Self.screen(Self.sidebar(selected: "General"), bar)

        #expect(!TapLanding.destinationTitled(label: "General", in: tree, tapped: Self.row("General")))
    }

    /// **Text outside any navigation bar does not name the destination**: the sidebar's own `StaticText` General is no title.
    @Test
    func textOutsideABarDoesNotNameIt() {
        let sidebarText = AXNode(type: "StaticText", frame: Self.frame(y: 120), label: "General")
        let tree = Self.screen(Self.sidebar(selected: "General", children: [sidebarText]), Self.bar(identifier: "About", title: "About"))

        #expect(!TapLanding.destinationTitled(label: "General", in: tree, tapped: Self.row("General")))
    }

    /// **Only the bar over the destination is asked, not any bar** (#126): in three columns the middle column's bar reads X while the detail is pushed deeper.
    @Test
    func aMiddleColumnsBarDoesNotNameADeeperDetail() {
        let tapped = Self.row("X", x: 330)
        let middle = AXNode(type: "NavigationBar", frame: AXNode.Frame(x: 320, y: 0, width: 320, height: 50), identifier: "X")
        let detail = AXNode(type: "NavigationBar", frame: AXNode.Frame(x: 640, y: 0, width: 392, height: 50), identifier: "Y")
        let tree = Self.screen(Self.sidebar(selected: "Menu"), middle, tapped, detail)

        #expect(!TapLanding.destinationTitled(label: "X", in: tree, tapped: tapped))
    }

    /// **The same three columns, the detail reading X, has landed.**
    @Test
    func aDetailBarNamingTheLabelLandsInThreeColumns() {
        let tapped = Self.row("X", x: 330)
        let middle = AXNode(type: "NavigationBar", frame: AXNode.Frame(x: 320, y: 0, width: 320, height: 50), identifier: "List")
        let detail = AXNode(type: "NavigationBar", frame: AXNode.Frame(x: 640, y: 0, width: 392, height: 50), identifier: "X")
        let tree = Self.screen(Self.sidebar(selected: "Menu"), middle, tapped, detail)

        #expect(TapLanding.destinationTitled(label: "X", in: tree, tapped: tapped))
    }

    /// **A title nested in an `Other`, the bar not directly under the application, still names it** (#126).
    @Test
    func aTitleNestedInAnOtherUnderAWrappedBarNamesIt() {
        let text = AXNode(type: "StaticText", frame: AXNode.Frame(x: 600, y: 24, width: 120, height: 22), label: "General")
        let nested = AXNode(type: "Other", frame: AXNode.Frame(x: 590, y: 20, width: 140, height: 30), children: [text])
        let bar = AXNode(type: "NavigationBar", frame: AXNode.Frame(x: 320, y: 0, width: 712, height: 50), children: [nested])
        let wrapper = AXNode(type: "Other", frame: AXNode.Frame(x: 320, y: 0, width: 712, height: 1376), children: [bar])
        let tree = Self.screen(Self.sidebar(selected: "General"), wrapper)

        #expect(TapLanding.destinationTitled(label: "General", in: tree, tapped: Self.row("General")))
    }

    /// **A `{n}` label and a no-break-space label name a title; a prefix does not** (#126).
    @Test
    func aTitleIsMatchedWholeWithSpacesAndPlaceholderReadButNotAsAPrefix() {
        let tapped = Self.row("x")
        func named(_ label: String, bar title: String) -> Bool {
            TapLanding.destinationTitled(label: label, in: Self.screen(Self.bar(title: title)), tapped: tapped)
        }

        #expect(named("Sailing {n}", bar: "Sailing 22"))
        #expect(named("CO₂ level", bar: "CO₂\u{00A0}level"))
        #expect(named("CO₂\u{00A0}level", bar: "CO₂ level"))
        #expect(!named("Sailing", bar: "Sailing 22"))
        #expect(!named("Sailing", bar: "Sailing, history"))
    }

    private static func screen(_ children: AXNode...) -> AXNode {
        AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 1032, height: 1376), children: children)
    }

    /// The sidebar, its selected row a button carrying `selected` as label.
    private static func sidebar(selected: String, children: [AXNode] = []) -> AXNode {
        let row = row(selected, children: children)
        return AXNode(type: "CollectionView", frame: AXNode.Frame(x: 0, y: 0, width: 320, height: 1376), children: [row])
    }

    private static func row(_ label: String, x: Double = 16, children: [AXNode] = []) -> AXNode {
        AXNode(
            type: "Button",
            frame: AXNode.Frame(x: x, y: 120, width: 288, height: 44),
            label: label,
            identifier: "com.apple.settings.\(label.lowercased())",
            isSelected: true,
            children: children
        )
    }

    private static func bar(identifier: String? = nil, label: String? = nil, title: String? = nil) -> AXNode {
        let text = title.map { [AXNode(type: "StaticText", frame: AXNode.Frame(x: 600, y: 24, width: 120, height: 22), label: $0)] } ?? []
        return AXNode(type: "NavigationBar", frame: AXNode.Frame(x: 320, y: 0, width: 712, height: 50), label: label, identifier: identifier, children: text)
    }

    private static func frame(y: Double) -> AXNode.Frame {
        AXNode.Frame(x: 16, y: y, width: 288, height: 44)
    }
}
