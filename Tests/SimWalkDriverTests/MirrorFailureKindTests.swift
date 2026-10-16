//
// Copyright © Agulhas Labs
//

import SimWalkCore
@testable import SimWalkDriver
import Testing

/// The mirror errors' kinds: setup problems of the Mac, the tool's own surprises, and lost focus on its own kind.
struct MirrorFailureKindTests {
    @Test
    func eachMirrorErrorReportsItsKind() {
        #expect(UsageFailureKind.of(MirrorControlError.noWindow) == .setupFailed)
        #expect(UsageFailureKind.of(MirrorControlError.captureMissing(path: "/x")) == .setupFailed)
        #expect(UsageFailureKind.of(MirrorControlError.systemEventsUnavailable(reason: "no")) == .setupFailed)
        #expect(UsageFailureKind.of(MirrorControlError.captureFailed(reason: "no")) == .toolError)
        #expect(UsageFailureKind.of(MirrorControlError.noMenuItem(title: "x", reason: "no")) == .toolError)
        #expect(UsageFailureKind.of(MirrorFocusRefusal(frontmost: "", moment: .beforeAction)) == .notFrontmost)
        #expect(UsageFailureKind.notFrontmost.rawValue == "not-frontmost")
    }
}
