//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkTestSupport
import Testing

/// `bundle audit --only appleContrast` over a bundle with no Apple audit record is a refused call, never an `ok` over nothing.
struct AppleAuditRuleCommandTests {
    private static func bundle(audited: Bool, in directory: TemporaryDirectory) throws -> CaptureBundle {
        let record = audited ? AppleAuditRecord(milliseconds: 1) : nil
        return try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "you", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.screen(rowType: "Button"), appleAudit: record),
        ])
    }

    @Test
    func namingAnAppleRuleOverABundleWithNoRecordIsRefused() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(audited: false, in: directory)
        let command = try BundleAuditCommand.parse([bundle.url.path, "--only", "appleContrast"])

        let thrown = #expect(throws: InputRefusal.self) { try command.answer() }

        #expect(thrown?.message == "appleContrast has no record to read: the walk did not run Apple's accessibility audit (walkbook \"appleAudit\": true, or walk --apple-audit)")
    }

    @Test
    func namingAnAppleRuleOverARecordedBundleRuns() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(audited: true, in: directory)
        let command = try BundleAuditCommand.parse([bundle.url.path, "--only", "appleContrast"])

        #expect(try command.answer().text.contains("[appleContrast] clean — 1 capture audited"))
    }

    @Test
    func aFullRunOverABundleWithNoRecordIsNotRefused() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(audited: false, in: directory)
        let command = try BundleAuditCommand.parse([bundle.url.path])

        #expect(try command.answer().text.contains("not recorded"))
    }
}
