//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// What `bundle inspect` reports about a bundle on disk, as opposed to what its manifest claims — the half that answers "is this still worth reading" a week after the walk.
struct CaptureBundleContentsTests {
    @Test
    func everyScreensArtefactsAreMeasuredAndTheTotalIncludesTheManifest() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleTests.writtenBundle(in: directory)

        let contents = CaptureBundleContents(bundle)
        let screens = contents.screens()

        // Two states, two artefacts each, "stub" in every one.
        #expect(screens.map(\.id) == ["today", "power-detail", "sleep-detail"])
        #expect(screens[0].captureCount == 2)
        #expect(screens[0].artefacts.count == 4)
        #expect(screens[0].bytes == 16)
        #expect(screens[1].artefacts.isEmpty)
        #expect(contents.totalBytes() > screens[0].bytes)
    }

    @Test
    func anAuditRecordIsMeasuredAndCountedInTheTotal() throws {
        var manifest = CaptureBundleTests.manifest()
        let screen = manifest.screens[0]
        let audited = CaptureManifest.StateCapture(
            screenID: screen.id,
            state: screen.captures[0].state,
            appleAudit: AppleAuditRecord(milliseconds: 5)
        )
        manifest.screens[0] = CaptureManifest.ScreenRecord(
            id: screen.id,
            outcome: screen.outcome,
            routeTaken: screen.routeTaken,
            captures: [audited] + screen.captures.dropFirst()
        )
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleTests.writtenBundle(in: directory, manifest: manifest)
        let audit = try #require(audited.appleAudit)
        let withStubRecord = CaptureBundleContents(bundle).totalBytes() // the record is 4 bytes of stub
        try Data("12345".utf8).write(to: CaptureBundleLayout.url(forRelativePath: audit.path, in: bundle.url))

        let contents = CaptureBundleContents(bundle)

        #expect(contents.screens()[0].artefacts.count == 5)
        #expect(contents.screens()[0].artefacts.contains { $0.path == audit.path && $0.bytes == 5 })
        #expect(contents.totalBytes() == withStubRecord + 1)
    }

    /// Presence is guaranteed by `CaptureBundle.read`; size is the claim it cannot make, and a zero-byte screenshot passes every structural check while depicting nothing.
    @Test
    func anArtefactThatIsPresentAndHoldsNothingIsReportedAsEmpty() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleTests.writtenBundle(in: directory)
        let capture = try #require(bundle.manifest.screens.first?.captures.first)
        try Data().write(to: bundle.screenshotURL(for: capture))

        let empty = CaptureBundleContents(bundle).emptyArtefacts()

        #expect(empty.map(\.path) == [capture.screenshotPath])
        #expect(empty.first?.bytes == 0)
    }

    /// "I looked and it holds nothing" and "I could not look" are different facts, and a failed `stat` returning zero asserted the first while knowing neither.
    @Test
    func anArtefactWhoseSizeCannotBeReadIsNotReportedAsEmpty() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleTests.writtenBundle(in: directory)
        let capture = try #require(bundle.manifest.screens.first?.captures.first)

        let contents = CaptureBundleContents(bundle, fileManager: Self.UnstattableFileManager(failingSuffix: capture.screenshotPath))

        #expect(contents.emptyArtefacts().isEmpty)
        #expect(contents.unmeasurableArtefacts().map(\.path) == [capture.screenshotPath])
    }

    /// A size that is short says so on the line that states it, rather than reading as the whole truth.
    @Test
    func aScreenCountsTheArtefactsItCouldNotMeasure() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleTests.writtenBundle(in: directory)
        let capture = try #require(bundle.manifest.screens.first?.captures.first)

        let screens = CaptureBundleContents(bundle, fileManager: Self.UnstattableFileManager(failingSuffix: capture.axTreePath)).screens()

        #expect(screens[0].unmeasurableCount == 1)
        #expect(screens[0].bytes == 12)
    }
}

private extension CaptureBundleContentsTests {
    /// A `FileManager` that cannot stat one path — a permissions failure, or a file that went away between the manifest being read and the size being asked for.
    final class UnstattableFileManager: FileManager, @unchecked Sendable {
        private let failingSuffix: String

        init(failingSuffix: String) {
            self.failingSuffix = failingSuffix
            super.init()
        }

        override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
            guard !path.hasSuffix(failingSuffix) else { throw CocoaError(.fileReadNoPermission) }
            return try super.attributesOfItem(atPath: path)
        }
    }
}
