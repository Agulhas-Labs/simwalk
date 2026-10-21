//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimWalkCore
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// A claim that cannot be written refuses as the lease store, which the usage log records as a tool error and not a runner failure (SimWalk#128).
struct LeaseErrorClaimTests {
    @Test
    func aClaimThatCannotBeWrittenRefusesAsAStoreFailureNamingTheLeaseStore() throws {
        let directory = try TemporaryDirectory()
        let leases = LeaseStore(directory: directory.url.appendingPathComponent("leases", isDirectory: true), isAlive: { _ in true })
        try FileManager.default.createDirectory(at: leases.directory, withIntermediateDirectories: true)
        try Data().write(to: leases.directory.appendingPathComponent(".walks"))

        let thrown = #expect(throws: LeaseError.self) {
            try LeaseError.takingClaim(udid: "UDID-1", in: leases)
        }

        let error = try #require(thrown)

        #expect(error.usageFailureKind == .toolError)
        guard case let .storeFailed(path, _) = error else {
            Issue.record("expected storeFailed, got \(error)")
            return
        }
        #expect(path == leases.directory.path)
    }
}
