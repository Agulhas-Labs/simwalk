//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimWalkCore
@testable import SimWalkDriver
import Testing

/// Coordination state is the account's, whatever `HOME` says: `HomeDirectories.account()` reads no environment, so a process under a scratch `HOME` still sees the user's leases.
struct StandardStoresAccountHomeTests {
    private static var account: String {
        FileManager.default.homeDirectoryForCurrentUser.path + "/.simwalk"
    }

    @Test
    func leasesLiveUnderTheAccountHome() {
        #expect(LeaseStore.standard().directory.path == Self.account + "/leases")
    }

    @Test
    func liveSessionsLiveUnderTheAccountHome() {
        #expect(LiveSessionStore.standard().directory.path == Self.account + "/sessions")
    }

    @Test
    func mirrorLockLivesUnderTheAccountHome() {
        #expect(MirrorCallLock.standard().file.path == Self.account + "/mirror/.lock")
    }
}
