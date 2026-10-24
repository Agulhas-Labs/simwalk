//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

@Suite("Replace retry and settled reads (SimWalk#214)")
struct ReplaceRetryTests {
    @Test func aTrailingPassThatRemovedTextIsRetried() {
        #expect(TypedTextLanding.shouldRetryTrailingEdge(before: "abcdef", after: "abc", pass: 1))
    }

    @Test func aTrailingPassThatRemovedNothingStops() {
        #expect(!TypedTextLanding.shouldRetryTrailingEdge(before: "abc", after: "abc", pass: 2))
    }

    @Test func aMaskedPassThatChangedTheTextAtTheSameLengthIsRetried() {
        #expect(TypedTextLanding.shouldRetryTrailingEdge(before: "12/34/5678", after: "12/34/____", pass: 1))
    }

    @Test func aClearedFieldStops() {
        #expect(!TypedTextLanding.shouldRetryTrailingEdge(before: "abc", after: "", pass: 1))
    }

    @Test func theBoundStopsAPassThatStillMadeProgress() {
        let limit = TypedTextLanding.trailingEdgePassLimit
        #expect(TypedTextLanding.shouldRetryTrailingEdge(before: "abcdef", after: "abc", pass: limit - 1))
        #expect(!TypedTextLanding.shouldRetryTrailingEdge(before: "abcdef", after: "abc", pass: limit))
    }

    @Test func aValueUnchangedForTheQuietPeriodIsSettled() {
        var settle = FieldValueSettle(quiet: 0.3, budget: 5)
        settle.record("LOUd", at: 0)

        #expect(!settle.isSettled(at: 0.1))
        settle.record("LOUD", at: 0.1)
        #expect(!settle.isSettled(at: 0.3))
        settle.record("LOUD", at: 0.4)
        #expect(settle.isSettled(at: 0.4))
        #expect(settle.value == "LOUD")
    }

    @Test func aValueStillChangingSettlesWhenTheBudgetRunsOut() {
        var settle = FieldValueSettle(quiet: 1, budget: 2)
        settle.record("a", at: 1.5)

        #expect(!settle.isSettled(at: 1.9))
        #expect(settle.isSettled(at: 2))
    }

    @Test func noReadIsNeverSettled() {
        #expect(!FieldValueSettle(quiet: 0.3, budget: 5).isSettled(at: 100))
    }

    @Test func aValueAfterANilReadRestartsTheQuietPeriod() {
        var settle = FieldValueSettle(quiet: 0.3, budget: 5)
        settle.record(nil, at: 0)
        settle.record("LOUD", at: 0.2)

        #expect(!settle.isSettled(at: 0.4))
        #expect(settle.isSettled(at: 0.5))
        #expect(settle.value == "LOUD")
    }

    @Test func aFieldThatNeverReadsSettlesAfterTheQuietPeriodWithNoValue() {
        var settle = FieldValueSettle(quiet: 0.3, budget: 5)
        settle.record(nil, at: 0)
        settle.record(nil, at: 0.2)

        #expect(!settle.isSettled(at: 0.2))
        settle.record(nil, at: 0.4)
        #expect(settle.isSettled(at: 0.4))
        #expect(settle.value == nil)
    }
}
