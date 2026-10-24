//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// The opt-in screenshot's wire shape (SimWalk#200): a request that asks for one, a response that carries it, and the device reply that drops it rather than lose the read.
struct LiveSessionScreenshotTests {
    private static func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try String(decoding: encoder.encode(value), as: UTF8.self)
    }

    /// A request that asks for a screenshot says so on the wire and reads back asking, on the simulator's file and the device's frame alike.
    @Test
    func aRequestThatAsksForAScreenshotKeepsItOnTheWire() throws {
        let request = LiveSessionRequest(n: 2, action: .read, screenshot: true)
        let json = try Self.json(request)

        #expect(json == #"{"action":"read","n":2,"screenshot":true}"#)
        #expect(try JSONDecoder().decode(LiveSessionRequest.self, from: Data(json.utf8)) == request)
        let device = DeviceSessionRequest(action: .read, screenshot: true)
        #expect(try Self.json(device) == #"{"action":"read","screenshot":true}"#)
        #expect(try JSONDecoder().decode(DeviceSessionRequest.self, from: Data(Self.json(device).utf8)) == device)
    }

    /// A request that does not ask writes no `screenshot` key, so every request is byte-identical to what it was before the key existed.
    @Test
    func aRequestThatDoesNotAskWritesNoScreenshotKey() throws {
        let step = Walkbook.RouteStep.tapPoint(label: "Next", point: [0.5, 0.5])
        let request = LiveSessionRequest(n: 1, action: .step, step: step, guardHash: "1a2b3c4d")

        #expect(try Self.json(LiveSessionRequest(n: 1, action: .read)) == #"{"action":"read","n":1}"#)
        #expect(try !Self.json(request).contains("screenshot"))
        #expect(try Self.json(DeviceSessionRequest(action: .read)) == #"{"action":"read"}"#)
        #expect(try JSONDecoder().decode(LiveSessionRequest.self, from: Data(#"{"n": 1, "action": "read"}"#.utf8)).screenshot == false)
        #expect(try JSONDecoder().decode(DeviceSessionRequest.self, from: Data(#"{"action": "read"}"#.utf8)).screenshot == false)
    }

    /// A device request keeps its screenshot flag when the runner numbers it.
    @Test
    func aNumberedDeviceRequestCarriesTheScreenshot() {
        #expect(DeviceSessionRequest(action: .read, screenshot: true).numbered(4) == LiveSessionRequest(n: 4, action: .read, screenshot: true))
        #expect(DeviceSessionRequest(action: .read).numbered(4).screenshot == false)
    }

    /// The PNG's bytes survive the response's JSON, and neither key is written when there is nothing to say.
    @Test
    func aResponseRoundTripsThePNGAndOmitsBothKeysWhenNil() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let response = LiveSessionResponse(n: 1, action: .read, screenshot: png)
        let refused = LiveSessionResponse(n: 2, action: .read, screenshotRefusal: "too big")

        let decoded = try CaptureBundle.decoder().decode(LiveSessionResponse.self, from: CaptureBundle.encoder().encode(response))
        #expect(decoded == response)
        #expect(decoded.screenshot == png)
        #expect(try CaptureBundle.decoder().decode(LiveSessionResponse.self, from: CaptureBundle.encoder().encode(refused)).screenshotRefusal == "too big")
        let plain = try Self.json(LiveSessionResponse(n: 3, action: .read))
        #expect(!plain.contains("screenshot"))
    }

    /// A reply whose screenshot takes it past the cap is sent without the screenshot, naming its size, rather than as the whole-reply failure that would lose the screen.
    @Test
    func anOverCapReplyDropsTheScreenshotAndKeepsTheRead() throws {
        let response = LiveSessionResponse(n: 7, action: .read, screenshot: Data(count: DeviceSessionFrame.replyCap + (1 << 20)))

        let frame = try DeviceSessionTransport.reply(response)
        let outbound = try DeviceSessionFrame.decode(DeviceSessionFrame.Outbound.self, from: frame)
        let sent = try #require(outbound.response)

        #expect(sent.n == 7)
        #expect(sent.action == .read)
        #expect(sent.failure == nil)
        #expect(sent.screenshot == nil)
        #expect(sent.screenshotRefusal == "the screenshot (17 MiB) would take the reply past the 16 MiB a host reads")
    }
}
