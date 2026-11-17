//
// Copyright © Agulhas Labs
//

import SimWalkCore
import Testing

struct HostLoadLineTests {
    @Test(arguments: HostLoadLine.signatures)
    func eachSignatureAtHighLoadGivesTheLine(signature: String) {
        #expect(HostLoadLine.line(failureTexts: ["Failed: \(signature) (x)"], loadAverage: 650, cores: 16) != nil)
    }

    @Test
    func aSignatureAtOrBelowFourTimesTheCoresGivesNothing() {
        #expect(HostLoadLine.line(failureTexts: ["Timed out while synthesizing event"], loadAverage: 64, cores: 16) == nil)
        #expect(HostLoadLine.line(failureTexts: ["Timed out while synthesizing event"], loadAverage: 10, cores: 16) == nil)
    }

    @Test
    func highLoadWithoutASignatureGivesNothing() {
        #expect(HostLoadLine.line(failureTexts: ["the app crashed"], loadAverage: 650, cores: 16) == nil)
    }

    @Test
    func anUnknownLoadGivesNothing() {
        #expect(HostLoadLine.line(failureTexts: ["Timed out while synthesizing event"], loadAverage: nil, cores: 16) == nil)
    }

    @Test
    func theLineReadsExactly() {
        #expect(HostLoadLine.line(failureTexts: ["Timed out while fetching snapshot"], loadAverage: 650.4, cores: 16)
            == "host: load 650 on 16 cores — XCTest timed out under it, so this is likely load, not the route; walk again when it falls")
    }
}
