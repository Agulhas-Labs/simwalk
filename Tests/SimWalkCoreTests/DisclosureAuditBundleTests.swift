//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// The half of the audit that reads a bundle off disk — which is the half that ships, and the half that had no test.
///
/// Every case here is about the verdict being true of the bundle it was given: what it read, what it could not, and what one row captured three times is a count of.
struct DisclosureAuditBundleTests {
    @Test
    func anAuditReadsEveryCaptureOfEveryScreenItCanOpen() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Fixture.write(in: directory, captures: [
            Fixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: Fixture.screen(rowType: "StaticText")),
            Fixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .dark), tree: Fixture.screen(rowType: "StaticText")),
        ])

        let rows = try DisclosureAffordanceAudit(bundle).rows()

        #expect(rows.count == 2)
        #expect(rows.map(\.stateSlug) == ["light", "dark"])
        #expect(rows.allSatisfy { $0.screenID == "progress" && $0.isControl == false })
    }

    /// The finding this whole round started from: a bundle of eleven screens where three were never captured reported "no disclosure rows found" and exited 0, over screens nothing had opened.
    @Test
    func aScreenTheWalkNeverCapturedIsNamedRatherThanCountingAsACleanBill() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Fixture.write(
            in: directory,
            captures: [Fixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: Fixture.plainScreen())],
            unreachable: ["power-detail", "sleep-detail"]
        )

        let findings = try DisclosureAffordanceAudit(bundle).findings()
        let rendered = DisclosureAuditSummary(findings, of: bundle).render()

        #expect(!findings.coverage.isComplete)
        #expect(rendered.contains("audited 1 of 3 screens"))
        #expect(rendered.contains("power-detail, sleep-detail"))
        #expect(rendered.contains("this verdict says nothing about them"))
        #expect(rendered.contains("no disclosure rows found"))
    }

    /// Round 2, finding 4: a screen recorded as `unexpectedScreen` holds real captures on disk, but of a different screen than the walkbook named — filing its rows under this screen's id would type another screen's shapes as this one's, so `rows()` skips it and `coverage()` names it rather than either silently.
    @Test
    func aWrongScreensCapturesAreExcludedFromRowsAndNamedInCoverage() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Fixture.write(
            in: directory,
            captures: [Fixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: Fixture.screen(rowType: "StaticText"))],
            outcome: .unexpectedScreen(expected: "progress-root", found: ["workouts-list-root"])
        )

        let rows = try DisclosureAffordanceAudit(bundle).rows()
        let coverage = DisclosureAffordanceAudit(bundle).coverage()

        #expect(rows.isEmpty)
        #expect(coverage.screensWrongScreen == ["progress"])
        #expect(coverage.screensRead.isEmpty)
        #expect(coverage.screensNotRead.isEmpty)
        #expect(!coverage.isComplete)
    }

    /// Round 3 nit: `rows()` skips a wrong screen's captures, so an unsettled one among them is a caveat about rows the audit never took — the coverage names the screen as the wrong one, and counts no capture of it as read mid-motion.
    @Test
    func aWrongScreensUnsettledCaptureIsNotCountedAsOneTheAuditRead() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Fixture.write(
            in: directory,
            captures: [Fixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: Fixture.plainScreen(), settled: false)],
            outcome: .unexpectedScreen(expected: "progress-root", found: ["workouts-list-root"])
        )

        let coverage = DisclosureAffordanceAudit(bundle).coverage()

        #expect(coverage.screensWrongScreen == ["progress"])
        #expect(coverage.unsettledCaptures.isEmpty)
    }

    /// A screen that recorded one state and failed on another is read, and is still not fully audited.
    @Test
    func aScreenCapturedOnlyInPartIsCountedAsReadAndFlaggedAsPartial() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Fixture.write(
            in: directory,
            captures: [Fixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: Fixture.screen(rowType: "StaticText"))],
            outcome: .captureFailed(reason: "state 'dark': no space left on device")
        )

        let coverage = DisclosureAffordanceAudit(bundle).coverage()

        #expect(coverage.screensRead == ["progress"])
        #expect(coverage.screensPartlyRead == ["progress"])
        #expect(!coverage.isComplete)
    }

    /// A bundle that holds everything says so plainly, so the caveat means something when it appears.
    @Test
    func aCompleteBundleStatesItsCoverageWithoutACaveat() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Fixture.write(in: directory, captures: [
            Fixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: Fixture.screen(rowType: "StaticText")),
        ])

        let rendered = try DisclosureAuditSummary(DisclosureAffordanceAudit(bundle).findings(), of: bundle).render()

        // The figure is in the verdict, and the caveat line under it is not printed at all: where the
        // audit read everything, that line would be the verdict's own words a second time.
        #expect(rendered.contains("ok — audited 1 of 1 screen\n"))
        #expect(!rendered.contains("says nothing about them"))
    }

    /// A row is a row however many times it was photographed: three states of one screen are one finding, not three.
    @Test
    func oneRowCapturedInThreeStatesCountsOnceAndNamesItsStates() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Fixture.write(in: directory, captures: [
            Fixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: Fixture.mixedScreen()),
            Fixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .dark), tree: Fixture.mixedScreen()),
            Fixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light, dynamicTypeSize: "UICTContentSizeCategoryAccessibilityL"), tree: Fixture.mixedScreen()),
        ])

        let rendered = try DisclosureAuditSummary(DisclosureAffordanceAudit(bundle).findings(), of: bundle).render()

        #expect(rendered.contains("2 disclosure rows: 1 typed as controls, 1 not"))
        // Slugs are lowercased by the layout, so the states read as the directories they were filed under.
        #expect(rendered.contains("[light, dark, light-dt_uictcontentsizecategoryaccessibilityl]"))
    }

    /// A screen whose only capture was taken while its tree was still populating is not a screen this verdict can speak for.
    ///
    /// Coverage asked whether a screen held captures, never whether they were honest — so a walk of eleven screens caught mid-motion rendered "audited 11 of 11 screens — no disclosure rows found" and exited 0, which is a clean bill of health over evidence the bundle itself flags as unreliable.
    @Test
    func aScreenCapturedBeforeItsTreeSettledDoesNotProduceAnUnqualifiedVerdict() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Fixture.write(in: directory, captures: [
            Fixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: Fixture.plainScreen(), settled: false),
        ])

        let findings = try DisclosureAffordanceAudit(bundle).findings()
        let rendered = DisclosureAuditSummary(findings, of: bundle).render()

        #expect(findings.coverage.unsettledCaptures == [CaptureManifest.CaptureReference(screenID: "progress", stateSlug: "light")])
        #expect(!findings.coverage.isComplete)
        #expect(rendered.contains("1 capture was read whose accessibility tree had not settled, or held only the app's chrome (progress/light)"))
        #expect(rendered.contains("no disclosure rows found"))
    }

    /// Two unsettled captures pluralise the caveat rather than repeating the singular wording.
    @Test
    func twoUnsettledCapturesPluraliseTheCaveat() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Fixture.write(in: directory, captures: [
            Fixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: Fixture.plainScreen(), settled: false),
            Fixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .dark), tree: Fixture.plainScreen(), settled: false),
        ])

        let findings = try DisclosureAffordanceAudit(bundle).findings()
        let rendered = DisclosureAuditSummary(findings, of: bundle).render()

        #expect(rendered.contains("2 captures were read whose accessibility tree had not settled, or held only the app's chrome (progress/light, progress/dark)"))
    }

    /// Both qualifications are stated, because they are different ones: nothing can be said about the screens that were never opened, and what was read of the moving one may not be what it settled into.
    @Test
    func anUnsettledCaptureIsNamedAlongsideTheScreensThatWereNeverOpened() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Fixture.write(
            in: directory,
            captures: [Fixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: Fixture.plainScreen(), settled: false)],
            unreachable: ["power-detail"]
        )

        let rendered = try DisclosureAuditSummary(DisclosureAffordanceAudit(bundle).findings(), of: bundle).render()

        #expect(rendered.contains("audited 1 of 2 screens — 1 holds no captures at all (power-detail); this verdict says nothing about them, and 1 capture was read whose accessibility tree had not settled, or held only the app's chrome (progress/light)"))
        #expect(rendered.contains("qualified — 1 screen holding no captures at all; 1 capture read before its accessibility tree settled, or while it held only the app's chrome · audited 1 of 2 screens"))
    }

    /// A tree this build cannot decode named nothing — not the bundle, not the screen, not the file — while `bundle inspect` on the same bundle printed cleanly.
    @Test
    func anAccessibilityTreeThisBuildCannotDecodeRefusesNamingTheArtefact() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Fixture.write(
            in: directory,
            captures: [Fixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: Fixture.plainScreen())],
            rawTreeBytes: #"{"raw":"Attributes: Application, label: 'RouteFixture'"}"#
        )

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try DisclosureAffordanceAudit(bundle).rows()
        })
        guard case let .artefactUnreadable(path, reason) = thrown else {
            Issue.record("expected an unreadable-artefact refusal, got \(thrown)")
            return
        }

        #expect(path.hasSuffix("screens/progress/light/ax-tree.json"))
        #expect(reason.contains("missing key 'type'"))
        // A current-format bundle is never told its format explains anything. Asserted here because the
        // format note's own test cannot tell an unconditionally-firing note from a correct one.
        #expect(!reason.contains("this bundle is format"))
    }

    /// A format-1 bundle is told what it is, rather than left looking corrupt — 8 of the bundles on the machine this was found on are format 1.
    @Test
    func aFormatOneBundlesTreeIsRefusedAsAFormatDifferenceRatherThanAsDamage() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Fixture.write(
            in: directory,
            captures: [Fixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: Fixture.plainScreen())],
            rawTreeBytes: #"{"raw":"Attributes: Application, label: 'RouteFixture'"}"#,
            formatVersion: 1
        )

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try DisclosureAffordanceAudit(bundle).rows()
        })

        #expect(thrown.description.contains("this bundle is format 1"))
        #expect(thrown.description.contains("walk it again to read it"))
    }

    /// The note is judged against the format that introduced the typed tree, not against whatever the current one happens to be.
    ///
    /// Format 3 bumped the version for the manifest's own vocabulary, nothing to do with trees. Judged against `currentFormatVersion`, a format-2 bundle — whose trees *are* typed — would have started being told that a later format replaced its trees with typed ones, one version after the round that established the note must never state a cause it did not check.
    @Test
    func abundleOfTheFormatThatIntroducedTheTypedTreeIsNotBlamedOnTheTreeShape() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Fixture.write(
            in: directory,
            captures: [Fixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: Fixture.plainScreen())],
            rawTreeBytes: #"{"raw":"Attributes: Application, label: 'RouteFixture'"}"#,
            formatVersion: CaptureManifest.typedTreeFormatVersion
        )

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try DisclosureAffordanceAudit(bundle).rows()
        })

        #expect(thrown.description.contains("ax-tree.json"))
        #expect(!thrown.description.contains("this bundle is format"))
    }

    /// Format 1 spans both tree shapes — 6 of the 15 bundles on this machine are format 1 with typed trees — so the note is conditioned on the bytes, not on the version.
    ///
    /// A damaged typed tree in one of those would otherwise be blamed on the format and its reader told to walk the bundle again, which is a confident wrong cause: the file is torn, and re-walking would produce a different bundle rather than fix this one.
    @Test(arguments: [
        // A typed tree whose second node lost its `type`: the same error as an untyped dump, one level down.
        #"{"type":"Application","frame":{"height":874,"width":402,"x":0,"y":0},"children":[{"frame":{"height":55,"width":374,"x":14,"y":184}}]}"#,
        // A tree truncated mid-write.
        #"{"type":"Application","frame":{"height":874,"#,
    ])
    func aFormatOneBundleWithADamagedTypedTreeIsNotBlamedOnTheFormat(_ bytes: String) throws {
        let directory = try TemporaryDirectory()
        let bundle = try Fixture.write(
            in: directory,
            captures: [Fixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: Fixture.plainScreen())],
            rawTreeBytes: bytes,
            formatVersion: 1
        )

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try DisclosureAffordanceAudit(bundle).rows()
        })

        #expect(thrown.description.contains("ax-tree.json"))
        #expect(!thrown.description.contains("this bundle is format"))
        #expect(!thrown.description.contains("walk it again"))
    }

    /// Format 1 is opened, not refused: its manifest, outcomes and screenshots are as true as the day they were written, and only its trees are of the older shape.
    @Test
    func aFormatOneBundleStillOpens() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Fixture.write(
            in: directory,
            captures: [Fixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: Fixture.plainScreen())],
            formatVersion: 1
        )

        let reread = try CaptureBundle.read(at: bundle.url)

        #expect(reread.manifest.formatVersion == 1)
        #expect(reread.manifest.screens.count == 1)
    }
}

private typealias Fixture = CaptureBundleFixture
