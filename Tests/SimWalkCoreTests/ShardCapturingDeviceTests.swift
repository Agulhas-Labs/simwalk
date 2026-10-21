//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

struct ShardCapturingDeviceTests {
    private static let record = CaptureManifest.ScreenRecord(id: "root", outcome: .captured, routeTaken: [])

    @Test func aSerialScreenRecordWritesNoCapturingDeviceKey() throws {
        let json = try #require(String(data: JSONEncoder().encode(Self.record), encoding: .utf8))

        #expect(!json.contains("capturedOn"))
    }

    @Test func aParallelScreenRecordRoundTripsItsCapturingDevice() throws {
        var record = Self.record
        record.capturedOn = CaptureManifest.CapturingDevice(name: "iPhone 17e", udid: "1688F4DB")
        let decoded = try JSONDecoder().decode(CaptureManifest.ScreenRecord.self, from: JSONEncoder().encode(record))

        #expect(decoded.capturedOn == record.capturedOn)
    }
}
