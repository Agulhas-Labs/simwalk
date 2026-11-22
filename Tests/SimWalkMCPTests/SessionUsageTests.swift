//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkMCP
import SimWalkTestSupport
import Testing

/// The session's saving is the ledger's total, so a repeat read's served bytes are charged to it.
struct SessionUsageTests {
    @Test
    func aRepeatReadChargesItsServedBytes() throws {
        let scratch = try TemporaryDirectory()
        let log = scratch.url.appendingPathComponent("usage.jsonl")
        let lines = try [400, 4000].map { bytes in
            let entry = UsageLog.Entry(
                timestamp: "2026-11-22T10:00:00Z", tool: "bundle.inspect", target: nil, milliseconds: 1, succeeded: true, error: nil,
                session: "s", screenshots: 1, imageTokens: 10000, answerBytes: bytes, priced: ["aaaaaaaaaaaa:10000"]
            )
            return try String(decoding: JSONEncoder().encode(entry), as: UTF8.self)
        }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: log)

        let usage = SessionUsage.scanning(log, after: SessionUsage(), session: "s")

        #expect(usage.tokensSaved == 10000 - TokenEstimate.tokens(forBytes: 4400))
    }
}
