//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// The one total over a log: every served byte is charged, and the zero floor applies to the total alone.
struct SavingsLedgerTests {
    static func line(tool: String = "bundle.inspect", priced: [String]? = nil, imageTokens: Int? = nil, answerBytes: Int?) -> UsageLog.Entry {
        UsageLog.Entry(
            timestamp: "2026-11-22T10:00:00Z", tool: tool, target: nil, milliseconds: 1, succeeded: true, error: nil,
            session: "s", screenshots: priced?.count, imageTokens: imageTokens, answerBytes: answerBytes, priced: priced
        )
    }

    /// A repeat read whose screenshots are all claimed already adds no tokens, and its bytes were still served.
    @Test
    func aRepeatReadChargesItsServedBytesAgainstTheTotal() {
        var ledger = SavingsLedger()
        ledger.add(Self.line(priced: ["aaaaaaaaaaaa:10000"], imageTokens: 10000, answerBytes: 400))
        ledger.add(Self.line(priced: ["aaaaaaaaaaaa:10000"], imageTokens: 10000, answerBytes: 4000))

        #expect(ledger.screenshotTokens == 10000)
        #expect(ledger.servedBytes == 4400)
        #expect(ledger.screenshots == 1)
        #expect(ledger.saved == 10000 - TokenEstimate.tokens(forBytes: 4400))
    }

    /// A line with an answer size and no screenshots was still served.
    @Test
    func aLineWithNoImageTokensStillChargesItsBytes() {
        var ledger = SavingsLedger()
        ledger.add(Self.line(priced: ["aaaaaaaaaaaa:10000"], imageTokens: 10000, answerBytes: 400))
        ledger.add(Self.line(answerBytes: 8000))

        #expect(ledger.servedBytes == 8400)
        #expect(ledger.saved == 10000 - TokenEstimate.tokens(forBytes: 8400))
    }

    /// The floor is at the total: an early expensive line is not forgiven by a later cheap one, and the total is never negative.
    @Test
    func theFloorIsAtTheTotalOnly() {
        var ledger = SavingsLedger()
        ledger.add(Self.line(priced: ["aaaaaaaaaaaa:100"], imageTokens: 100, answerBytes: 4000))
        #expect(ledger.saved == 0)
        ledger.add(Self.line(priced: ["bbbbbbbbbbbb:5000"], imageTokens: 5000, answerBytes: 40))

        #expect(ledger.saved == 5100 - TokenEstimate.tokens(forBytes: 4040))

        var over = SavingsLedger()
        over.add(Self.line(priced: ["cccccccccccc:10"], imageTokens: 10, answerBytes: 100_000))
        #expect(over.saved == 0)
    }
}
