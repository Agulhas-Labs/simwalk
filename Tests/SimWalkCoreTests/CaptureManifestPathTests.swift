//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// A manifest read off disk never went through the layout-deriving initialiser, so these are the cases where a hand-made or tampered manifest tries to say a path the layout would not.
///
/// Each of these inspected as a clean pass before the paths were checked against the layout rather than merely for existence.
struct CaptureManifestPathTests {
    @Test
    func aCapturePointingAtAnotherStatesArtefactIsRefused() throws {
        let manifest = try Self.manifestWithCaptureJSON(
            screenshot: "screens/today/light/screen.png",
            axTree: "screens/today/light/ax-tree.json",
            theme: "dark"
        )

        let problems = CaptureManifestValidator.problems(in: manifest)

        #expect(problems.count == 2)
        #expect(problems.allSatisfy {
            if case .misfiledArtefact = $0 {
                true
            } else {
                false
            }
        })
        #expect(problems[0].description.contains("screens/today/dark/screen.png"))
    }

    @Test
    func aCapturePointingOutsideTheBundleIsRefusedEvenWhenThatFileExists() throws {
        let directory = try TemporaryDirectory()
        let bundleURL = directory.url.appendingPathComponent("escape.\(CaptureBundleLayout.directoryExtension)")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try Data("png".utf8).write(to: directory.url.appendingPathComponent("outside.png"))
        let manifest = try Self.manifestWithCaptureJSON(
            screenshot: "../outside.png",
            axTree: "../outside.png",
            theme: "light"
        )

        // The existence check alone is satisfied — the file really is there, just not in the bundle.
        #expect(CaptureManifestValidator.missingArtefactProblems(for: manifest, in: bundleURL).isEmpty)
        #expect(!CaptureManifestValidator.problems(in: manifest).isEmpty)
    }

    @Test
    func anEscapingPathIsRefusedWhenTheBundleIsRead() throws {
        let directory = try TemporaryDirectory()
        let bundleURL = directory.url.appendingPathComponent("escape.\(CaptureBundleLayout.directoryExtension)")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try Data("png".utf8).write(to: directory.url.appendingPathComponent("outside.png"))
        let manifest = try Self.manifestWithCaptureJSON(screenshot: "../outside.png", axTree: "../outside.png", theme: "light")
        try CaptureBundle.encoder().encode(manifest).write(to: CaptureBundle.manifestURL(in: bundleURL))

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try CaptureBundle.read(at: bundleURL)
        })

        #expect(thrown.description.contains("a path is derived, never stated"))
    }

    @Test
    func aClaimedAuditRecordThatIsAbsentIsReportedMissingWithItsPath() throws {
        let directory = try TemporaryDirectory()
        let manifest = try Self.manifestWithCaptureJSON(
            screenshot: "screens/today/light/screen.png",
            axTree: "screens/today/light/ax-tree.json",
            theme: "light",
            auditPath: "screens/today/light/apple-audit.json"
        )
        try FileManager.default.createDirectory(at: directory.url.appendingPathComponent("screens/today/light"), withIntermediateDirectories: true)
        for name in ["screen.png", "ax-tree.json"] {
            try Data("x".utf8).write(to: directory.url.appendingPathComponent("screens/today/light/\(name)"))
        }

        let problems = CaptureManifestValidator.missingArtefactProblems(for: manifest, in: directory.url)

        #expect(problems == [.artefactMissing(screenID: "today", stateSlug: "light", expectedPath: "screens/today/light/apple-audit.json")])
    }

    @Test
    func aClaimedAuditRecordThatIsPresentOrUnclaimedAddsNoMissingProblem() throws {
        let directory = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: directory.url.appendingPathComponent("screens/today/light"), withIntermediateDirectories: true)
        for name in ["screen.png", "ax-tree.json", "apple-audit.json"] {
            try Data("x".utf8).write(to: directory.url.appendingPathComponent("screens/today/light/\(name)"))
        }
        let audited = try Self.manifestWithCaptureJSON(
            screenshot: "screens/today/light/screen.png",
            axTree: "screens/today/light/ax-tree.json",
            theme: "light",
            auditPath: "screens/today/light/apple-audit.json"
        )
        let unaudited = try Self.manifestWithCaptureJSON(
            screenshot: "screens/today/light/screen.png",
            axTree: "screens/today/light/ax-tree.json",
            theme: "light"
        )

        #expect(CaptureManifestValidator.missingArtefactProblems(for: audited, in: directory.url).isEmpty)
        #expect(CaptureManifestValidator.missingArtefactProblems(for: unaudited, in: directory.url).isEmpty)
        #expect(CaptureManifestValidator.problems(in: audited).isEmpty)
        #expect(CaptureManifestValidator.problems(in: unaudited).isEmpty)
    }

    @Test
    func anAuditRecordPathThatIsNotTheLayoutsIsReportedMisfiled() throws {
        let manifest = try Self.manifestWithCaptureJSON(
            screenshot: "screens/today/light/screen.png",
            axTree: "screens/today/light/ax-tree.json",
            theme: "light",
            auditPath: "screens/today/dark/apple-audit.json"
        )

        let problems = CaptureManifestValidator.problems(in: manifest)

        #expect(problems == [.misfiledArtefact(
            screenID: "today",
            stateSlug: "light",
            stated: "screens/today/dark/apple-audit.json",
            expected: "screens/today/light/apple-audit.json"
        )])
    }

    @Test
    func twoScreenRecordsDifferingOnlyByCaseAreRefusedAsACollision() {
        var manifest = CaptureBundleTests.manifest()
        var shouted = manifest.screens[0]
        shouted = CaptureManifest.ScreenRecord(
            id: "Today",
            outcome: .captured,
            routeTaken: [.tab(label: "Today")],
            captures: [CaptureManifest.StateCapture(screenID: "Today", state: Walkbook.CaptureState(theme: .light))]
        )
        manifest.screens = [manifest.screens[0], shouted]

        let problems = CaptureManifestValidator.problems(in: manifest)

        #expect(problems.contains(.collidingScreenIDs(slug: "today", ids: ["Today", "today"])))
    }

    /// Builds a manifest through the *decoder*, which is the path a hand-made manifest takes — the layout-deriving initialiser is not available to it.
    private static func manifestWithCaptureJSON(screenshot: String, axTree: String, theme: String, auditPath: String? = nil) throws -> CaptureManifest {
        let audit = auditPath.map {
            #", "appleAudit": { "path": "\#($0)", "milliseconds": 5, "issueCount": 0, "failed": false }"#
        } ?? ""
        let json = """
        {
          "formatVersion": 1, "walkName": "w", "appBundleID": "a", "appBuildHash": "b",
          "walkbookHash": "c",
          "device": { "name": "d", "udid": "u", "osVersion": "26.0" },
          "startedAt": "2026-08-16T08:00:00.000Z", "finishedAt": "2026-08-16T08:00:01.000Z",
          "screens": [
            { "id": "today", "outcome": { "captured": {} }, "routeTaken": [],
              "captures": [
                { "state": { "theme": "\(theme)" }, "screenshotPath": "\(screenshot)", "axTreePath": "\(axTree)"\(audit) }
              ] }
          ]
        }
        """
        return try CaptureBundle.decoder().decode(CaptureManifest.self, from: Data(json.utf8))
    }
}
