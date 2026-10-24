//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// The options a read takes for a screenshot, and the state directory's keep-newest-20 (SimWalk#200).
struct ScreenshotOptionTests {
    @Test
    func noOptionIsNoRequestAndAScaleOrALabelImpliesOne() throws {
        #expect(try ScreenshotOption.request(screenshot: false, scale: nil, of: nil) == nil)
        #expect(try ScreenshotOption.request(screenshot: true, scale: nil, of: nil) == ScreenshotFit.Request(scale: 1))
        #expect(try ScreenshotOption.request(screenshot: false, scale: 2, of: nil) == ScreenshotFit.Request(scale: 2))
        #expect(try ScreenshotOption.request(screenshot: false, scale: nil, of: "Done") == ScreenshotFit.Request(scale: 1, label: "Done"))
    }

    @Test
    func aScaleOutsideOneToThreeIsRefusedNamingIt() {
        #expect(throws: ScreenshotOption.Refusal.self) { try ScreenshotOption.request(screenshot: false, scale: 4, of: nil) }
        do {
            _ = try ScreenshotOption.request(screenshot: true, scale: 4, of: nil)
        } catch {
            #expect("\(error)".contains("4"))
        }
    }

    @Test
    func pruneKeepsTheNewestTwentyOfTwentyTwoAndTouchesNothingElse() throws {
        let directory = try TemporaryDirectory()
        let manager = FileManager.default
        for index in 0 ..< 22 {
            let url = directory.url.appendingPathComponent("inspect-\(index).png")
            try Data([1]).write(to: url)
            try manager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_790_000_000 + Double(index))], ofItemAtPath: url.path)
        }
        try Data([1]).write(to: directory.url.appendingPathComponent("other.png"))

        ScreenshotOption.prune(directory.url)

        let names = try Set(manager.contentsOfDirectory(atPath: directory.url.path))

        #expect(names.count == 21)
        #expect(!names.contains("inspect-0.png") && !names.contains("inspect-1.png"))
        #expect(names.contains("inspect-2.png") && names.contains("inspect-21.png") && names.contains("other.png"))
    }

    @Test
    func anAbsentImageIsTheRunnersRefusalOrTheCallersReason() throws {
        let tree = ScreenshotFitTests.tree()
        let request = try #require(ScreenshotFit.Request(scale: 1))
        let url = URL(fileURLWithPath: "/nonexistent/x.png")

        #expect(ScreenshotOption.outcome(png: nil, refusal: "too big", absentReason: "none", tree: tree, request: request, to: url) == .refused("too big"))
        #expect(ScreenshotOption.outcome(png: nil, refusal: nil, absentReason: "none", tree: tree, request: request, to: url) == .refused("none"))
    }
}
