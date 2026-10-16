//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// The focus guard's decision over scripted frontmost names: it clears only on iPhone Mirroring, and refuses naming what was there once ten polls have passed.
struct MirrorFocusTests {
    /// Ten polls naming another app refuse on the tenth, naming it; none before clears or refuses.
    @Test
    func tenPollsOfAnotherAppRefuseNamingIt() {
        var focus = MirrorFocus()

        let decisions = (1 ... 10).map { _ in focus.take("Terminal") }

        #expect(decisions.dropLast().allSatisfy(Self.isPollAgain))
        #expect(Self.refusal(decisions.last) == "Terminal")
        #expect(MirrorFocus.maxPolls == 10)
        #expect(MirrorFocus.pollInterval == 0.2)
    }

    /// Mirroring named on the third poll clears there.
    @Test
    func mirroringOnTheThirdPollClears() {
        var focus = MirrorFocus()

        let decisions = ["Terminal", "Terminal", MirrorFocus.appName].map { focus.take($0) }

        #expect(decisions.prefix(2).allSatisfy(Self.isPollAgain))
        #expect(Self.isCleared(decisions[2]))
        #expect(focus.polls == 3)
    }

    /// An empty name — System Events naming nothing — never clears, and the refusal says so rather than quoting an empty string.
    @Test
    func anEmptyNameRefuses() {
        var focus = MirrorFocus()

        let last = (1 ... 10).map { _ in focus.take("") }.last

        #expect(Self.refusal(last) == "")
        #expect(MirrorFocusRefusal(frontmost: "", moment: .beforeAction).localizedDescription.contains("System Events named no frontmost process"))
    }

    /// A poll after the refusal refuses too, Mirroring or not: a loop that ignored the refusal can never clear late.
    @Test
    func aPollPastTheLastNeverClears() {
        var focus = MirrorFocus()
        for _ in 1 ... 10 {
            _ = focus.take("Terminal")
        }

        let late = focus.take(MirrorFocus.appName)

        #expect(Self.refusal(late) == MirrorFocus.appName)
    }

    /// The single read clears on Mirroring and otherwise refuses at the moment it was asked about, naming both.
    @Test
    func theSingleReadRefusesNamingTheAppAndTheMoment() throws {
        let frame = MirrorFocusRefusal(frontmost: "Terminal", moment: .beforeFrame(4)).localizedDescription
        let gesture = MirrorFocusRefusal(frontmost: "Safari", moment: .duringGesture).localizedDescription
        _ = try MirrorFocus.recheck(MirrorFocus.appName, at: .duringGesture)

        #expect(throws: MirrorFocusRefusal(frontmost: "Safari", moment: .duringGesture)) {
            try MirrorFocus.recheck("Safari", at: .duringGesture)
        }
        #expect(frame.contains("'Terminal'"))
        #expect(frame.contains("frame 4"))
        #expect(gesture.contains("'Safari'"))
        #expect(gesture.contains("during the gesture"))
    }

    private static func isPollAgain(_ decision: MirrorFocus.Decision) -> Bool {
        if case .pollAgain = decision {
            return true
        }
        return false
    }

    private static func isCleared(_ decision: MirrorFocus.Decision) -> Bool {
        if case .cleared = decision {
            return true
        }
        return false
    }

    /// The name a refusal named, `nil` for any other decision.
    private static func refusal(_ decision: MirrorFocus.Decision?) -> String? {
        if case let .refused(frontmost) = decision {
            return frontmost
        }
        return nil
    }
}
