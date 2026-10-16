//
// Copyright © Agulhas Labs
//

import CoreGraphics
import Foundation
import SimWalkCore
@testable import SimWalkDriver
import Testing

/// The two refusals the mirror's first live runs showed it needed: a window that is not the phone, and a System Events that would not answer.
struct MirrorControlRefusalTests {
    /// Mirroring's onboarding window (640×662 pt) is larger than the phone's (383×843 pt) but not phone-shaped: with both on screen the phone is picked, with only it the lookup refuses.
    @Test
    func onlyAPhoneShapedWindowIsPicked() throws {
        let phone = Self.windowInfo(number: 1018, bounds: CGRect(x: 672, y: 118, width: 383, height: 843))
        let welcome = Self.windowInfo(number: 1030, bounds: CGRect(x: 400, y: 100, width: 640, height: 662))

        let picked = try MirrorWindow.frame(among: [welcome, phone])

        #expect(picked.windowID == 1018)
        #expect(throws: MirrorControlError.noWindow) {
            try MirrorWindow.frame(among: [welcome])
        }
    }

    /// A window exactly 1.5 times as tall as it is wide is phone-shaped; one a point short of it is not.
    @Test
    func theShapeBoundaryIsOnePointFiveTimesTheWidth() throws {
        let boundary = Self.windowInfo(number: 1, bounds: CGRect(x: 0, y: 0, width: 400, height: 600))
        let short = Self.windowInfo(number: 2, bounds: CGRect(x: 0, y: 0, width: 400, height: 599))

        #expect(try MirrorWindow.frame(among: [boundary]).windowID == 1)
        #expect(throws: MirrorControlError.noWindow) {
            try MirrorWindow.frame(among: [short])
        }
    }

    /// An AppleScript error from System Events refuses as its own cause, after one activation and one read, never as lost focus to retry.
    @Test
    func aSystemEventsErrorIsNotReadAsLostFocus() {
        let unavailable = MirrorControlError.systemEventsUnavailable(reason: "Not authorized to send Apple events to System Events., error -1743")
        var reads = 0
        var activations = 0
        let focus = MirrorFocusGuard(activate: { activations += 1 }, readFrontmost: { () throws(MirrorControlError) -> String in reads += 1
            throw unavailable
        }, pause: { _ in })

        #expect(throws: unavailable) {
            _ = try focus.clear()
        }
        #expect(throws: unavailable) {
            _ = try focus.recheck(at: .beforeFrame(2))
        }
        #expect(activations == 1)
        #expect(reads == 2)
    }

    /// The refusal names where to grant the permission, and the error's own message and number.
    @Test
    func theRefusalNamesTheAutomationPermission() {
        let text = MirrorControlError.systemEventsUnavailable(reason: "Not authorized, error -1743").errorDescription ?? ""

        #expect(text.contains("Privacy & Security → Automation (System Events)"))
        #expect(text.contains("Not authorized, error -1743"))
    }

    private static func windowInfo(number: Int, bounds: CGRect) -> [String: Any] {
        [
            "kCGWindowNumber": NSNumber(value: number),
            "kCGWindowOwnerName": MirrorFocus.appName,
            "kCGWindowLayer": NSNumber(value: 0),
            "kCGWindowBounds": bounds.dictionaryRepresentation,
        ]
    }
}
