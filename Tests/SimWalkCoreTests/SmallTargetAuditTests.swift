//
// Copyright © Agulhas Labs
//

@testable import SimWalkCore
import Testing

/// `smallTarget`: an enabled control under 44×44 points, less what the calibration showed is not a target of its own.
struct SmallTargetAuditTests {
    private static func node(_ type: String, _ x: Double, _ y: Double, _ width: Double, _ height: Double, label: String? = nil, enabled: Bool = true, children: [AXNode] = []) -> AXNode {
        AXNode(type: type, frame: AXNode.Frame(x: x, y: y, width: width, height: height), label: label, isEnabled: enabled, children: children)
    }

    private static func evaluate(_ children: [AXNode]) -> LabelRuleResult {
        let screen = node("Application", 0, 0, 402, 874, children: children)
        return SmallTargetAudit().evaluate(screen, screenID: "you", stateSlug: "light")
    }

    @Test
    func aSmallEnabledButtonFires() {
        let result = Self.evaluate([Self.node("Button", 20, 100, 30, 30, label: "Close")])

        #expect(result.findings.count == 1)
        #expect(result.findings.first?.label == "Close")
        #expect(result.findings.first?.note == "30×30 pt")
        #expect(result.examined == 1)
    }

    @Test
    func aFullSizeButtonDoesNot() {
        let result = Self.evaluate([Self.node("Button", 20, 100, 44, 44, label: "Close")])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 1)
    }

    @Test
    func floatNoiseUnder44IsNotSmallButARealShortfallIs() {
        let noisy = Self.evaluate([Self.node("Button", 20, 100, 57, 43.999999999999986, label: "Add")])
        let short = Self.evaluate([Self.node("Button", 20, 100, 57, 43.9, label: "Add")])

        #expect(noisy.findings.isEmpty)
        #expect(noisy.examined == 1)
        #expect(short.findings.count == 1)
    }

    @Test
    func aDisabledZeroSizedOrOffScreenControlDoesNot() {
        let result = Self.evaluate([
            Self.node("Button", 20, 100, 30, 30, label: "Off", enabled: false),
            Self.node("Button", 20, 200, 0, 0, label: "Unlaid"),
            Self.node("Button", 20, 2000, 30, 30, label: "Below the fold"),
        ])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 0)
    }

    /// The Settings calibration: 28-point buttons in 53-point cells.
    @Test
    func aSmallControlAloneInAFullSizeCellDoesNot() {
        let cell = Self.node("Cell", 20, 100, 362, 53, label: "About", children: [Self.node("Button", 34, 110, 88, 28, label: "About")])

        let result = Self.evaluate([cell])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 1)
    }

    /// The Apple Account sheet (#74): the table lists the same button inside a group and again beside it.
    @Test
    func theSameButtonReachedUnderTwoParentsIsCountedOnce() {
        let button = Self.node("Button", 38, 395.7, 229, 33, label: "Don't have an Apple Account?")
        let table = Self.node("Table", 0, 300, 402, 300, children: [Self.node("Other", 0, 390, 402, 50, children: [button]), button])

        let result = Self.evaluate([table])

        #expect(result.findings.map(\.label) == ["Don't have an Apple Account?"])
        #expect(result.examined == 1)
    }

    /// SimWalk#75: an element reached first inside a cell it is the row of, then beside it, is a finding — the copy beside the cell is not tapped through it.
    @Test
    func anElementExemptUnderOneParentButNotTheOtherStillFires() {
        let button = Self.node("Button", 20, 400, 360, 28, label: "About")
        let table = Self.node("Table", 0, 300, 402, 300, children: [Self.node("Cell", 0, 390, 402, 53, children: [button]), button])

        let result = Self.evaluate([table])

        #expect(result.findings.map(\.label) == ["About"])
        #expect(result.examined == 1)
    }

    /// SimWalk#75: two elements that look alike side by side in one parent are two targets, not one element reported twice.
    @Test
    func twoLookAlikeControlsInOneParentAreBothExamined() {
        let button = Self.node("Button", 20, 400, 20, 20)
        let group = Self.node("Other", 0, 390, 402, 50, children: [button, button])

        let result = Self.evaluate([group])

        #expect(result.findings.count == 2)
        #expect(result.examined == 2)
    }

    /// A small button that is not the row is a small target in a big cell.
    @Test
    func aTrailingInfoButtonInATextRowFiresAndASwitchBesideOneDoesNotHideIt() {
        let info = Self.node("Button", 340, 114, 24, 24, label: "Info")
        let row = Self.node("Cell", 20, 100, 362, 53, label: "Storage", children: [Self.node("StaticText", 34, 115, 200, 22, label: "Storage"), info])
        let toggle = Self.node("Switch", 300, 170, 51, 31, label: "Wi-Fi")
        let beside = Self.node("Cell", 20, 160, 362, 53, label: "Wi-Fi", children: [toggle, Self.node("Button", 250, 170, 30, 30, label: "Help")])

        let result = Self.evaluate([row, beside])

        #expect(result.findings.map(\.label) == ["Info", "Help"])
    }

    @Test
    func aControlSpanningMostOfTheCellIsTheRow() {
        let cell = Self.node("Cell", 20, 100, 362, 53, children: [Self.node("Button", 20, 110, 300, 28, label: "Anything")])

        #expect(Self.evaluate([cell]).findings.isEmpty)
    }

    @Test
    func twoSmallControlsSharingACellEachFire() {
        let cell = Self.node("Cell", 20, 100, 362, 53, children: [
            Self.node("Button", 34, 110, 30, 28, label: "Edit"),
            Self.node("Button", 300, 110, 30, 28, label: "Delete"),
        ])

        #expect(Self.evaluate([cell]).findings.count == 2)
    }

    /// The Settings calibration: the search field's dictation button is the field's accessory.
    @Test
    func aControlInsideATextFieldOrAnotherControlDoesNot() {
        let field = Self.node("SearchField", 20, 800, 336, 38, children: [Self.node("Button", 336, 811, 17, 22, label: "Dictate")])
        let button = Self.node("Button", 20, 100, 44, 44, label: "Row", children: [Self.node("Button", 30, 110, 20, 20, label: "Inner")])

        let result = Self.evaluate([field, button])

        #expect(result.findings.isEmpty)
    }

    @Test
    func anInlineLinkDoesNotButAStandaloneOneDoes() {
        let text = Self.node("StaticText", 20, 100, 300, 20, label: "Read the terms")
        let inline = Self.node("Link", 200, 100, 80, 20, label: "terms")
        let standalone = Self.node("Link", 20, 400, 80, 20, label: "Help")

        let result = Self.evaluate([text, inline, standalone])

        #expect(result.findings.map(\.label) == ["Help"])
    }

    /// A web article's byline link has no text ancestor or sibling, so only the web view says it is inline text (SimWalk#239).
    ///
    /// Does not pin how deep the web view sits.
    @Test
    func aLinkInsideAWebViewIsInlineTextAndIsNotJudged() {
        let link = Self.node("Link", 19, 147, 152, 23, label: "NetNewsWire Blog", children: [Self.node("StaticText", 19, 147, 152, 23, label: "NetNewsWire Blog")])
        let banner = Self.node("Other", 19, 125, 380, 68, label: "banner", children: [Self.node("Other", 19, 125, 289, 67, children: [link])])
        let webView = Self.node("WebView", 0, 0, 402, 874, children: [Self.node("WebView", 0, 0, 402, 874, children: [banner])])

        let result = Self.evaluate([Self.node("ScrollView", 0, 0, 402, 874, children: [webView])])

        #expect(result.findings.isEmpty)
    }

    @Test
    func theSameLinkOutsideAWebViewIsJudged() {
        let link = Self.node("Link", 19, 147, 152, 23, label: "NetNewsWire Blog", children: [Self.node("StaticText", 19, 147, 152, 23, label: "NetNewsWire Blog")])
        let banner = Self.node("Other", 19, 125, 380, 68, label: "banner", children: [Self.node("Other", 19, 125, 289, 67, children: [link])])

        let result = Self.evaluate([Self.node("ScrollView", 0, 0, 402, 874, children: [banner])])

        #expect(result.findings.map(\.label) == ["NetNewsWire Blog"])
    }

    @Test
    func aTextLikeButtonOnAScreenWithoutAWebViewIsJudged() {
        let button = Self.node("Button", 32, 754, 105, 20, label: "Privacy Policy")
        let cell = Self.node("Cell", 16, 739, 370, 87, children: [Self.node("Other", 16, 739, 370, 87, children: [button])])

        let result = Self.evaluate([Self.node("CollectionView", 0, 0, 402, 874, children: [cell])])

        #expect(result.findings.map(\.label) == ["Privacy Policy"])
    }

    @Test
    func barControlsAndSwitchesAreLeftOut() {
        let bar = Self.node("TabBar", 0, 780, 402, 94, children: [Self.node("Button", 10, 790, 30, 30, label: "Home")])
        let toggle = Self.node("Switch", 319, 334, 51, 31, label: "Cycle tracking")

        let result = Self.evaluate([bar, toggle])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 0)
    }

    /// Apple's Settings reports no frame for the application node; the window's is the screen.
    @Test
    func aRootWithNoFrameFallsBackToTheWindow() {
        let window = Self.node("Window", 0, 0, 402, 874, children: [Self.node("Button", 20, 100, 30, 30, label: "Close")])
        let root = Self.node("Application", 0, 0, 0, 0, children: [window])

        let result = SmallTargetAudit().evaluate(root, screenID: "root", stateSlug: "light")

        #expect(result.findings.count == 1)
    }

    /// A cell a hair under 44 (SimWalk#118) is still a full-size target, so the control tapped through it is not a finding; one genuinely under is.
    @Test
    func aCellWithinTheToleranceOf44StillCarriesItsRowButAShorterOneDoesNot() {
        func cell(height: Double) -> AXNode {
            Self.node("Cell", 20, 100, 362, height, label: "About", children: [Self.node("Button", 34, 105, 88, 28, label: "About")])
        }

        let within = Self.evaluate([cell(height: 43.995)])
        let outside = Self.evaluate([cell(height: 43.9)])

        #expect(within.findings.isEmpty)
        #expect(within.examined == 1)
        #expect(outside.findings.count == 1)
    }
}
