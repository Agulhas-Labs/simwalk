//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// The host's half of a device exchange: the request and its response filed under the runner's number, as a simulator's session lays them out, and the token they travel with.
struct DeviceSessionFilingTests {
    /// A filed exchange reads back as a simulator's would: the request under the runner's number, with that number inside it, and the response beside it.
    @Test
    func anexchangeIsFiledUnderTheRunnersNumber() throws {
        let directory = try TemporaryDirectory()
        let channel = LiveSessionChannel(layout: LiveSessionLayout(directory: directory.url))
        try channel.prepare()
        let request = DeviceSessionRequest(action: .step, step: .tap(label: "Next"), guardHash: "1a2b3c4d")
        let response = LiveSessionResponse(n: 3, action: .step, failure: "no element labelled Next")

        try channel.file(request, answeredBy: response)

        #expect(try channel.request(3) == LiveSessionRequest(n: 3, action: .step, step: .tap(label: "Next"), guardHash: "1a2b3c4d"))
        #expect(try channel.response(to: 3) == response)
        #expect(channel.layout.requestNumbers() == [3])
    }

    /// A second exchange under a number already filed is refused, and the first is left as it was: one number, one answer.
    @Test
    func asecondFilingUnderOneNumberIsRefused() throws {
        let directory = try TemporaryDirectory()
        let channel = LiveSessionChannel(layout: LiveSessionLayout(directory: directory.url))
        try channel.prepare()
        try channel.file(DeviceSessionRequest(action: .read), answeredBy: LiveSessionResponse(n: 1, action: .read))

        #expect(throws: LiveSessionError.alreadyFiled(number: 1, path: channel.layout.request(1).path)) {
            try channel.file(DeviceSessionRequest(action: .end), answeredBy: LiveSessionResponse(n: 1, action: .end))
        }
        #expect(try channel.request(1)?.action == .read)
        #expect(try channel.response(to: 1)?.action == .read)
    }

    /// A drawn token is 64 lowercase hex digits, a fresh one each time, and matches only itself.
    @Test
    func atokenIsSixtyFourHexDigitsAndMatchesOnlyItself() throws {
        let token = try DeviceSessionToken.random()
        let other = try DeviceSessionToken.random()

        #expect(DeviceSessionToken(hex: token.hex) == token)
        #expect(token != other)
        #expect(token.matches(token.hex))
        #expect(!token.matches(other.hex))
        #expect(!token.matches(String(token.hex.dropLast())))
        #expect(DeviceSessionToken(hex: String(repeating: "A", count: 64)) == nil)
        #expect(!"\(token)".contains(token.hex))
    }
}
