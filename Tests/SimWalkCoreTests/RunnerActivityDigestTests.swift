//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// SimWalk#50: a failed runner's activities read down to the dozen lines that matter, from a real result bundle's JSON.
///
/// The fixture is `xcresulttool get test-results activities` over the result bundle of `RouteFixtureFailureSpecimen`, a UI test of `Fixtures/RouteFixture` that fails twice on purpose, with its UUIDs and paths replaced by synthetic ones. It is an app UI test rather than a walk: a walkbook cannot make the runner's XCTest fail (a screen's problem is a CAPTURE FAILED outcome and the test passes), and the activity tree is XCTest's, not the test's. Remake it with the commands in `FailureSpecimenUITests.swift`.
struct RunnerActivityDigestTests {
    @Test
    func theTenActivitiesBeforeTheLastFailureAreListedInOrderWithoutTheTriage() throws {
        let element = "`\"Hub row 99\" StaticText`"
        let predicate = "Checking `Expect predicate `existsNoRetry == 1` for object \"Hub row 99\" StaticText`"

        let digest = try #require(RunnerActivityDigest.parse(Self.fixture()))

        #expect(digest.recentActivities == [
            "Synthesize event",
            "kXCTAttachmentLegacySnapshot",
            "kXCTAttachmentLegacySynthesizedEvent",
            "Wait for dev.simwalk.route-fixture to idle",
            "Waiting 1.0s for \"Hub row 99\" StaticText to exist",
            predicate,
            "Checking existence of \(element)",
            "Capturing element debug description",
            "Debug description for \(element)",
            "Checking existence of \(element)",
        ])
    }

    @Test
    func theFailureIsTheLastRecordedAndTheEarlierOnesAreCounted() throws {
        let digest = try #require(RunnerActivityDigest.parse(Self.fixture()))

        #expect(digest.failure == "XCTAssertTrue failed - Hub drew no rows at all")
        #expect(digest.earlierFailures == 1)
    }

    @Test
    func theAttachmentsAreThoseOfTheTriageJustBeforeTheFailure() throws {
        let digest = try #require(RunnerActivityDigest.parse(Self.fixture()))

        #expect(digest.triageAttachments.map(\.name) == [
            "App UI hierarchy for dev.simwalk_0_11111111-2222-3333-4444-000000000037.route-fixture",
            "UI Snapshot 2026-10-16 at 02.26.37 pm",
        ])
        #expect(digest.hierarchyAttachments.map(\.uuid) == ["11111111-2222-3333-4444-000000000038"])
    }

    /// The export names each file by its attachment's identifier: these are the names the real export of the fixture's bundle wrote.
    @Test
    func theExportedHierarchyIsTheFileNamedByItsAttachmentsIdentifier() throws {
        let written = ["11111111-2222-3333-4444-000000000029.txt", "11111111-2222-3333-4444-000000000038.txt", "manifest.json"]

        let digest = try #require(RunnerActivityDigest.parse(Self.fixture()))

        #expect(digest.exportedHierarchyFiles(among: written) == ["11111111-2222-3333-4444-000000000038.txt"])
        #expect(digest.exportedHierarchyFiles(among: ["manifest.json"]).isEmpty)
    }

    /// Nothing to show is `nil`, never a throw: this only ever adds lines to a refusal already being made.
    @Test(arguments: ["", "{}", "[]", #"{"testRuns":[]}"#, #"{"testRuns":[{"activities":[{"title":"Set Up","isAssociatedWithFailure":false}]}]}"#, "<plist/>"])
    func anEmptyOrForeignDocumentHasNothingToShow(_ json: String) {
        let digest = RunnerActivityDigest.parse(Data(json.utf8))

        #expect(digest == nil)
    }

    /// A parent marked because its child failed is context; the child is the failure.
    @Test
    func aParentMarkedForItsChildsFailureIsListedAsAStep() throws {
        let json = #"{"testRuns":[{"activities":[{"title":"Tap Button","isAssociatedWithFailure":true,"childActivities":[{"title":"Find the Any (Element at index 1)","isAssociatedWithFailure":false},{"title":"Failed to get matching snapshot: No matches found","isAssociatedWithFailure":true}]}]}]}"#

        let digest = try #require(RunnerActivityDigest.parse(Data(json.utf8)))

        #expect(digest.recentActivities == ["Tap Button", "Find the Any (Element at index 1)"])
        #expect(digest.failure == "Failed to get matching snapshot: No matches found")
        #expect(digest.earlierFailures == 0)
        #expect(digest.triageAttachments.isEmpty)
    }

    /// The round-2 review's finding: the triage credited to a failure has to be one recorded since the *previous* failure — a last failure with no triage of its own must export nothing, never an earlier failure's hierarchy under its own label.
    @Test
    func alastFailureWithNoTriageOfItsOwnCreditsNoEarlierHierarchy() throws {
        let json = #"{"testRuns":[{"activities":[{"title":"Collecting debug information to assist test failure triage","isAssociatedWithFailure":false,"attachments":[{"name":"App UI hierarchy for com.example.app","uuid":"EARLY1"}]},{"title":"First assertion failed","isAssociatedWithFailure":true},{"title":"Tap Button","isAssociatedWithFailure":false},{"title":"Second assertion failed","isAssociatedWithFailure":true}]}]}"#

        let digest = try #require(RunnerActivityDigest.parse(Data(json.utf8)))

        #expect(digest.failure == "Second assertion failed")
        #expect(digest.earlierFailures == 1)
        #expect(digest.triageAttachments.isEmpty)
        #expect(digest.hierarchyAttachments.isEmpty)
    }

    private static func fixture(sourceLocation: SourceLocation = #_sourceLocation) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "runner-failure-activities", withExtension: "json", subdirectory: "Fixtures"), sourceLocation: sourceLocation)
        return try Data(contentsOf: url)
    }
}
