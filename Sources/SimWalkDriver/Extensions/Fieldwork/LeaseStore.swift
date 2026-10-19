//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimWalkCore

public extension LeaseStore {
    /// The machine's own leases — never moved by `SIMWALK_USAGE_LOG`, since a lease that a test or a review could not see would not keep it off a device.
    ///
    /// Under the account home (``HomeDirectories/account()``), not `HOME`: a process under a scratch `HOME` must still see the user's leases.
    static func standard() -> LeaseStore {
        LeaseStore(directory: HomeDirectories.account()
            .appendingPathComponent("leases", isDirectory: true))
    }
}
