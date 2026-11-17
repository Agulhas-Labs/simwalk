//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import SimWalkDriver

/// What a walk or dry run does after its runner timed out launching the app twice, or once with the output already written to (SimWalk#266).
struct LaunchTimeoutCheck {
    /// Launches the app with `simctl` as the walkbook at `executedPath` first launches it, and the one line saying what that showed.
    ///
    /// The launch arguments and environment are the first state of the first screen of the walkbook the runner was handed (a `--screens` subset or a shard's), and none when it does not load.
    static func line(attempts: Int, executedPath: String, bundleID: String, simulator: Simulator, now: Date, shell: Shell) -> String {
        let state = (try? WalkbookLoader.load(contentsOf: URL(fileURLWithPath: executedPath)))?.screens.first?.states.first
        let context = SimctlLaunchCheck.context(for: simulator, now: now, shell: shell)
        return SimctlLaunchCheck.perform(
            on: simulator,
            bundleID: bundleID,
            arguments: state?.launchArguments ?? [],
            environment: state?.launchEnvironment(over: [:]) ?? [:],
            shell: shell
        ).line(attempts: attempts, bootedAgo: context.bootedAgo, loadAverage: context.loadAverage)
    }
}
