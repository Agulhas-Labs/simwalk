//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimWalkCore
@testable import SimWalkDriver
import Testing

/// Coordination state is the account's, whatever `HOME` or `CFFIXED_USER_HOME` says, so a process under a scratch home still sees the user's leases.
///
/// `HomeDirectories.account()` reads the password database; these compare with `getpwuid`, never `homeDirectoryForCurrentUser`, which follows `CFFIXED_USER_HOME`.
struct StandardStoresAccountHomeTests {
    private static var account: String {
        (getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? "") + "/.simwalk"
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
