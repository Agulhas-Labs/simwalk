//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// `unexpectedScreen`'s own shape checks, split out of `CaptureBundleIntegrityTests` (round 2) so that file stays under its length limit — every case here is about the one outcome that is *expected* to carry captures, and about what a record claiming it must and must not say.
struct UnexpectedScreenManifestValidationTests {
    /// Unlike every refusal above, a screen filed as the wrong one is *expected* to carry captures — the wrong screen is evidence a reader needs kept, not evidence a refusal denies.
    @Test
    func anUnexpectedScreenCarryingCapturesIsNotAProblem() {
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(
                id: "activity-detail",
                outcome: .unexpectedScreen(expected: "activity-detail-root", found: ["workouts-list-root"]),
                routeTaken: [.tab(label: "Activity")],
                captures: [CaptureManifest.StateCapture(screenID: "activity-detail", state: Walkbook.CaptureState(theme: .light))]
            ),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest).isEmpty)
    }

    /// Round 4 nit: named as the blank expectation it is, not as a capture failure with no reason.
    @Test
    func anUnexpectedScreenNamingNoExpectedValueIsAProblem() {
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(id: "activity-detail", outcome: .unexpectedScreen(expected: "  ", found: ["workouts-list-root"]), routeTaken: []),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest) == [.unexpectedScreenBlankExpected(screenID: "activity-detail")])
    }

    /// Round 2 nit: `ExpectedScreenCheck` never produces an `unexpectedScreen` naming no identifier at all — a mismatch always names what mismatched.
    @Test
    func anUnexpectedScreenNamingNothingFoundIsAProblem() {
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(
                id: "activity-detail",
                outcome: .unexpectedScreen(expected: "activity-detail-root", found: []),
                routeTaken: [],
                captures: [CaptureManifest.StateCapture(screenID: "activity-detail", state: Walkbook.CaptureState(theme: .light))]
            ),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest) == [.unexpectedScreenNamesNothingFound(screenID: "activity-detail")])
    }

    /// Round 2 nit: `found` lists what mismatched, so it can never legitimately include `expected` itself — a manifest claiming that names no mismatch.
    @Test
    func anUnexpectedScreenFoundListingTheExpectedValueIsAProblem() {
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(
                id: "activity-detail",
                outcome: .unexpectedScreen(expected: "activity-detail-root", found: ["activity-detail-root"]),
                routeTaken: [],
                captures: [CaptureManifest.StateCapture(screenID: "activity-detail", state: Walkbook.CaptureState(theme: .light))]
            ),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest) == [.unexpectedScreenFoundNamesExpected(screenID: "activity-detail")])
    }

    /// Round 2, finding 3: a screen can be the wrong one *and* have a state the device discarded at the same time, so `unexpectedScreen` may now carry `refusedStates` exactly as `stateNotApplied` does.
    @Test
    func anUnexpectedScreenMayCarryRefusedStates() {
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(
                id: "activity-detail",
                outcome: .unexpectedScreen(expected: "activity-detail-root", found: ["workouts-list-root"], reason: "states 'light' and 'dark' produced byte-identical screenshots"),
                routeTaken: [],
                captures: [CaptureManifest.StateCapture(screenID: "activity-detail", state: Walkbook.CaptureState(theme: .light))],
                refusedStates: [Walkbook.CaptureState(theme: .dark)]
            ),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest).isEmpty)
    }

    /// Round 3, finding 2: `unexpectedScreen` is a verdict a format-4 reader has no case for, so a bundle holding one declares format 5 or later — and a reader of the formats before it refuses it by name ("format 5, this build reads 4, 3, 2, 1") rather than reporting a good manifest as torn at `screens[0].outcome`.
    @Test
    func aReaderOfTheFormatsBeforeTheVerdictRefusesABundleHoldingItByName() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleTests.writtenBundle(in: directory, manifest: Self.manifest(screens: [Self.wrongScreen()]))
        let data = try Data(contentsOf: CaptureBundle.manifestURL(in: bundle.url))
        // The list the last build before `unexpectedScreen` shipped with.
        let formatFourReader = [4, 3, 2, 1]

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try CaptureBundle.requireReadableFormat(of: data, at: "manifest.json", readable: formatFourReader)
        })
        guard case let .unsupportedFormatVersion(_, found, supported) = thrown else {
            Issue.record("expected a refusal by format version, got \(thrown)")
            return
        }

        #expect(found == CaptureManifest.currentFormatVersion)
        #expect(supported == formatFourReader)
    }

    /// The bump is one this build reads back: a bundle holding the verdict opens, outcome intact.
    @Test
    func thisBuildReadsBackABundleHoldingAWrongScreen() throws {
        let directory = try TemporaryDirectory()
        let written = try CaptureBundleTests.writtenBundle(in: directory, manifest: Self.manifest(screens: [Self.wrongScreen()]))

        let read = try CaptureBundle.read(at: written.url)

        #expect(read.manifest.formatVersion == CaptureManifest.currentFormatVersion)
        #expect(read.manifest.screens.first?.outcome == Self.wrongScreen().outcome)
    }

    /// A record claiming the verdict in a format before its own is one no walk wrote, refused the way refused states before format 4 are.
    @Test
    func anUnexpectedScreenInAFormatBeforeItsOwnIsAProblem() {
        var manifest = Self.manifest(screens: [Self.wrongScreen()])
        manifest.formatVersion = CaptureManifest.unexpectedScreenFormatVersion - 1

        #expect(CaptureManifestValidator.problems(in: manifest) == [
            .unexpectedScreenBeforeItsFormat(screenID: "activity-detail", formatVersion: CaptureManifest.unexpectedScreenFormatVersion - 1),
        ])
    }

    private static func wrongScreen() -> CaptureManifest.ScreenRecord {
        CaptureManifest.ScreenRecord(
            id: "activity-detail",
            outcome: .unexpectedScreen(expected: "activity-detail-root", found: ["workouts-list-root"]),
            routeTaken: [.tab(label: "Activity")],
            captures: [CaptureManifest.StateCapture(screenID: "activity-detail", state: Walkbook.CaptureState(theme: .light))]
        )
    }

    private static func manifest(screens: [CaptureManifest.ScreenRecord]) -> CaptureManifest {
        var manifest = CaptureBundleTests.manifest()
        manifest.screens = screens
        return manifest
    }
}
