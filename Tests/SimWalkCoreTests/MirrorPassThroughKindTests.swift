//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// How the border and corner refusal is logged: a caller's bad argument, not a failure of the tool.
struct MirrorPassThroughKindTests {
    @Test
    func aPassThroughIsAnInputRefusal() throws {
        let refusal = try MirrorWindowFrame.PassThrough(fraction: MirrorFraction(x: 0.01, y: 0.5))

        #expect(UsageFailureKind.of(refusal) == .inputRefused)
    }
}
