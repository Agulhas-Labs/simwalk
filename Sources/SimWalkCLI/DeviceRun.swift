//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import SimWalkDriver

extension WalkCommand {
    /// One prepared device and what its walk needs of `prepare`: the plan, the runner, the lease it runs under and whether the walk may reboot it.
    struct DeviceRun {
        /// The walkbook as the caller named it.
        let book: Walkbook
        let outputURL: URL
        let source: RunnerSource
        let simulator: Simulator
        /// The installed app's hash, which the runner writes into what it produces.
        let buildHash: String
        /// The walkbook file the runner is handed.
        let executedPath: String
        let runner: RunnerInvocation
        /// The lease the device is walked under, which the walk renews.
        let lease: WalkLease
        /// The library to insert into the app's launch, when animations are off.
        let animationsOffLibrary: String?
        /// Whether this walk may reboot the device (``DeviceSettle/mayReboot(_:requested:leased:)``), which also decides whether a setup is made on it.
        let owned: Bool
    }
}
