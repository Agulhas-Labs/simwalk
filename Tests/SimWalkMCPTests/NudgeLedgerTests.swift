//
// Copyright © Agulhas Labs
//

import Foundation
import os
@testable import SimWalkMCP
import SimWalkTestSupport
import Testing

/// A context hears the nudge at most once per ``NudgeLedger/memory``, and never on its first call (SimWalk#110).
struct NudgeLedgerTests {
    /// Once the memory has passed, the context is new again: its first call goes through, its next is refused.
    @Test
    func afterTheMemoryTheContextsFirstCallGoesThroughAgain() throws {
        let scratch = try TemporaryDirectory()
        let then = Date()
        let directory = scratch.url.appendingPathComponent("nudges")
        let ledger = NudgeLedger(directory: directory, now: { then })

        #expect(!ledger.refuses(context: "s1", call: "a"))
        #expect(ledger.refuses(context: "s1", call: "b"))
        #expect(!ledger.refuses(context: "s1", call: "c"))

        // Records are aged by their modification date, which the clock cannot move: set it back past the memory.
        let aged = then.addingTimeInterval(-NudgeLedger.memory - 60)
        let contextDirectory = directory.appendingPathComponent("s1")
        for name in try FileManager.default.contentsOfDirectory(atPath: contextDirectory.path) {
            try FileManager.default.setAttributes([.modificationDate: aged], ofItemAtPath: contextDirectory.appendingPathComponent(name).path)
        }

        #expect(!ledger.refuses(context: "s1", call: "d"))
        #expect(ledger.refuses(context: "s1", call: "e"))
    }

    /// SimWalk#119: calls racing in one context cannot each be refused: the cap holds under concurrency.
    @Test
    func concurrentCallsAreRefusedNoMoreThanTheCap() throws {
        let scratch = try TemporaryDirectory()
        let ledger = NudgeLedger(directory: scratch.url.appendingPathComponent("nudges"))
        // Many contexts, one race each: a single race can be lost by luck.
        for round in 0 ..< 40 {
            let context = "s\(round)"
            // Past the first call, which is only remembered, so every racer is eligible for the refusal.
            #expect(!ledger.refuses(context: context, call: "first"))
            let refusals = OSAllocatedUnfairLock(initialState: 0)

            DispatchQueue.concurrentPerform(iterations: 16) { index in
                if ledger.refuses(context: context, call: "call-\(index)") {
                    refusals.withLock { $0 += 1 }
                }
            }

            #expect(refusals.withLock { $0 } <= NudgeLedger.cap, "context \(context)")
        }
    }
}
