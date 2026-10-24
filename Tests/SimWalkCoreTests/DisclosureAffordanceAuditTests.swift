//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// The audit exists to answer one question a reviewer previously answered by hand: does a row that draws a chevron open anything, and is it typed so that anyone not looking at pixels can tell?
struct DisclosureAffordanceAuditTests {
    /// The geometry is taken from a real capture — the glyph is 7.7 × 13.7 with its trailing edge 8pt inside the row's — so the thresholds are pinned against the thing they were derived from rather than against themselves.
    @Test
    func aRowDrawingATrailingChevronIsFound() {
        let rows = DisclosureAffordanceAudit.disclosureRows(
            in: Self.screen(rowType: "StaticText"),
            screenID: "progress",
            stateSlug: "light"
        )

        #expect(rows.count == 1)
        #expect(rows.first?.type == "StaticText")
        #expect(rows.first?.label == "Log one meal")
        #expect(rows.first?.isControl == false)
    }

    @Test
    func theSameRowTypedAsAButtonIsFoundAndCountsAsAControl() {
        let rows = DisclosureAffordanceAudit.disclosureRows(
            in: Self.screen(rowType: "Button"),
            screenID: "browse",
            stateSlug: "light"
        )

        #expect(rows.first?.isControl == true)
    }

    /// A row with no trailing glyph is not a disclosure row, however much text it carries — the chevron is the whole claim.
    @Test
    func aRowWithoutATrailingGlyphIsNotFound() {
        let plain = AXNode(
            type: "StaticText",
            frame: AXNode.Frame(x: 14, y: 184, width: 374, height: 55),
            label: "Log one meal",
            children: [AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 196, width: 90, height: 16), label: "Log one meal")]
        )

        #expect(DisclosureAffordanceAudit.disclosureRows(in: plain, screenID: "s", stateSlug: "light").isEmpty)
    }

    /// A glyph floating in the middle of a row is not a disclosure indicator; only the trailing edge means "this opens".
    @Test
    func aGlyphThatIsNotAtTheTrailingEdgeIsNotADisclosure() {
        let midRow = Self.row(type: "StaticText", glyphX: 200)

        #expect(DisclosureAffordanceAudit.disclosureRows(in: midRow, screenID: "s", stateSlug: "light").isEmpty)
    }

    /// The system scroll indicator is a labelled element with a thin thumb at its trailing edge, which is the whole shape of a disclosure row; it is a bar, not a row (SimWalk#228). Built from a real capture; its thumb is off the bar's centre (the centred thumb is pinned next).
    @Test
    func aScrollIndicatorIsNotADisclosureRow() {
        let bar = AXNode(
            type: "Other",
            frame: AXNode.Frame(x: 387, y: 122, width: 30, height: 704),
            label: "Vertical scroll bar, 2 pages",
            value: "0%",
            children: [AXNode(type: "Other", frame: AXNode.Frame(x: 414, y: 816, width: 3, height: 7))]
        )
        let list = AXNode(type: "CollectionView", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), children: [bar])

        #expect(DisclosureAffordanceAudit.disclosureRows(in: list, screenID: "s", stateSlug: "light").isEmpty)
    }

    /// A mid-scroll bar has its thumb at the bar's vertical centre, so only the scroll-indicator guard rejects it (SimWalk#228).
    @Test
    func aScrollIndicatorWithItsThumbAtTheCentreIsNotADisclosureRow() {
        let bar = AXNode(
            type: "Other",
            frame: AXNode.Frame(x: 387, y: 122, width: 30, height: 704),
            label: "Vertical scroll bar, 2 pages",
            value: "50%",
            children: [AXNode(type: "Other", frame: AXNode.Frame(x: 414, y: 470, width: 3, height: 7))]
        )
        let list = AXNode(type: "CollectionView", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), children: [bar])

        #expect(DisclosureAffordanceAudit.disclosureRows(in: list, screenID: "s", stateSlug: "light").isEmpty)
    }

    /// A glyph at the bottom edge of a short labelled row is not a chevron, which is drawn at the row's vertical centre; this pins that test alone, with a row no scroll indicator could be (SimWalk#228).
    @Test
    func aGlyphAtTheRowsBottomEdgeIsNotADisclosure() {
        let rowNode = AXNode(
            type: "Other",
            frame: AXNode.Frame(x: 14, y: 100, width: 374, height: 44),
            label: "Notifications",
            children: [AXNode(type: "Other", frame: AXNode.Frame(x: 377, y: 137, width: 3, height: 7))]
        )

        #expect(DisclosureAffordanceAudit.disclosureRows(in: rowNode, screenID: "s", stateSlug: "light").isEmpty)
    }

    /// The control for the two above: a settings row with its chevron centred is still found (SimWalk#228).
    @Test
    func aCentredChevronInASettingsRowIsStillADisclosure() {
        let settingsRow = AXNode(
            type: "Button",
            frame: AXNode.Frame(x: 16, y: 156.33, width: 370, height: 52),
            label: "App Icon",
            children: [
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 31.67, y: 170, width: 108, height: 25), label: "App Icon"),
                AXNode(type: "Image", frame: AXNode.Frame(x: 360.67, y: 176.33, width: 7, height: 12), identifier: "chevron.forward"),
            ]
        )

        #expect(DisclosureAffordanceAudit.disclosureRows(in: settingsRow, screenID: "s", stateSlug: "dark").count == 1)
    }

    /// The finding is a minority against a majority: rows typed two ways in one bundle.
    @Test
    func rowsTypedTwoWaysAreInconsistentAndUniformOnesAreNot() {
        let mixed = DisclosureAffordanceAudit.Findings(
            controlRows: [Self.found(type: "Button")],
            uncontrolledRows: [Self.found(type: "StaticText")],
            coverage: Self.everyScreenRead
        )
        #expect(mixed.isInconsistent)

        let uniform = DisclosureAffordanceAudit.Findings(
            controlRows: [Self.found(type: "Button")],
            uncontrolledRows: [],
            coverage: Self.everyScreenRead
        )
        #expect(!uniform.isInconsistent)
    }

    /// A bundle that types every disclosure row the same way is reported as establishing nothing, rather than as a pass — the audit has no standing to call one app's whole convention wrong.
    @Test
    func aUniformlyUncontrolledBundleSaysItProvesNothing() {
        let rendered = DisclosureAuditSummary(
            DisclosureAffordanceAudit.Findings(
                controlRows: [],
                uncontrolledRows: [Self.found(type: "StaticText")],
                coverage: Self.everyScreenRead
            ),
            of: Self.bundle
        ).render()

        #expect(rendered.contains("none typed as a control"))
        #expect(rendered.contains("not evidence they are correct"))
    }

    /// The report names the majority beside the minority, which is the whole reason it is more useful than the finding alone.
    @Test
    func theReportNamesTheRowsThatAreTypedCorrectly() {
        let rendered = DisclosureAuditSummary(
            DisclosureAffordanceAudit.Findings(
                controlRows: [Self.found(type: "Button", screenID: "browse", label: "Heart")],
                uncontrolledRows: [Self.found(type: "StaticText", screenID: "progress", label: "Log one meal")],
                coverage: Self.everyScreenRead
            ),
            of: Self.bundle
        ).render()

        #expect(rendered.contains("not typed as controls"))
        #expect(rendered.contains("progress:"))
        #expect(rendered.contains("the same shape, typed as controls"))
        #expect(rendered.contains("browse:"))
    }

    /// A one-screen caveat is written in the singular: the line read "1 hold no captures at all", "1 were captured only in part", "audited 1 of 1 screens".
    @Test
    func aCoverageCaveatAboutOneScreenIsWrittenInTheSingular() {
        let both = Self.rendered(coverage: DisclosureAffordanceAudit.Coverage(
            screensRead: ["progress"],
            screensNotRead: ["power-detail"],
            screensPartlyRead: ["progress"]
        ))
        let one = Self.rendered(coverage: DisclosureAffordanceAudit.Coverage(
            screensRead: ["progress"],
            screensNotRead: [],
            screensPartlyRead: ["progress"]
        ))

        #expect(both.contains("audited 1 of 2 screens — 1 holds no captures at all (power-detail); 1 was captured only in part (progress); this verdict says nothing about them"))
        #expect(one.contains("audited 1 of 1 screen — 1 was captured only in part (progress);"))
        // The verdict states the same two gaps as qualifications, which is the half a caller gates on.
        #expect(both.contains("qualified — 1 screen holding no captures at all; 1 screen captured only in part · audited 1 of 2 screens"))
    }

    /// Round 2, finding 4: a screen recorded as `unexpectedScreen` is neither read (its rows would be filed under the wrong id) nor unopened (the walk did reach and record something) — its own coverage clause names it rather than the verdict silently folding it into either.
    @Test
    func aWrongScreenIsNamedInItsOwnCoverageClauseRatherThanReadOrUnread() {
        let rendered = Self.rendered(coverage: DisclosureAffordanceAudit.Coverage(
            screensRead: [],
            screensNotRead: [],
            screensWrongScreen: ["progress"]
        ))

        #expect(rendered.contains("qualified — 1 screen that captured a different screen than the walkbook expected · audited 0 of 1 screen"))
        #expect(rendered.contains("1 captured a different screen than expected (progress)"))
    }

    /// A bundle with nothing on disk behind it: these suites are about the verdict's words, and a bundle whose artefacts are absent weighs nothing, so no context line joins the answer to be asserted around.
    private static let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/audit.simwalk"), manifest: CaptureBundleTests.manifest())

    /// A verdict over a bundle that holds everything it set out to, so a test of the finding is not also a test of the coverage caveat.
    private static let everyScreenRead = DisclosureAffordanceAudit.Coverage(screensRead: ["s"], screensNotRead: [])

    /// The verdict over a given coverage, with no rows in it — the coverage line is what these read.
    private static func rendered(coverage: DisclosureAffordanceAudit.Coverage) -> String {
        DisclosureAuditSummary(
            DisclosureAffordanceAudit.Findings(controlRows: [], uncontrolledRows: [], coverage: coverage),
            of: bundle
        ).render()
    }

    private static func found(type: String, screenID: String = "s", label: String = "row") -> DisclosureRow {
        DisclosureRow(
            screenID: screenID,
            stateSlug: "light",
            type: type,
            label: label,
            frame: AXNode.Frame(x: 14, y: 184, width: 374, height: 55)
        )
    }

    /// A row whose trailing glyph sits where the real chevron does: 7.7 × 13.7, its right edge 8pt inside the row's.
    private static func row(type: String, glyphX: Double = 372.15) -> AXNode {
        AXNode(
            type: type,
            frame: AXNode.Frame(x: 14, y: 184, width: 374, height: 55),
            label: "Log one meal",
            children: [
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 196, width: 90, height: 16), label: "Log one meal"),
                AXNode(type: "Other", frame: AXNode.Frame(x: glyphX, y: 204.8, width: 7.7, height: 13.7)),
            ]
        )
    }

    private static func screen(rowType: String) -> AXNode {
        AXNode(
            type: "Application",
            frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
            children: [row(type: rowType)]
        )
    }
}
