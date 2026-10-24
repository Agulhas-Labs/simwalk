//
// Copyright © Agulhas Labs
//

import Foundation

/// Wall-clock milliseconds per segment of a walk, filled as each segment ends — the progress file's `summary` and the result file's `timings` are this one value (`Docs/SIMWALK-PROGRESS.md` §2, §4).
///
/// The split is what makes a slow walk attributable: a slow `bootMs` is the simulator, a slow `runMs` is the app, and `buildMs` is the *runner's* `build-for-testing` (cached after the first run), never the app's build. A segment not yet ended, or not taken at all (`installMs` without an `appPath`), is `nil` and omitted.
public struct PhaseTimings: Codable, Equatable, Sendable {
    public var bootMs: Int?
    public var installMs: Int?
    public var buildMs: Int?
    public var runMs: Int?
    /// The whole run, start to end — the result's, which the progress file leaves out until the end.
    public var totalMs: Int?
    /// Each shard's marks and the merge, for a `--parallel` walk; absent for a serial one.
    public var parallel: ParallelTimings?

    public init(bootMs: Int? = nil, installMs: Int? = nil, buildMs: Int? = nil, runMs: Int? = nil, totalMs: Int? = nil, parallel: ParallelTimings? = nil) {
        self.bootMs = bootMs
        self.installMs = installMs
        self.buildMs = buildMs
        self.runMs = runMs
        self.totalMs = totalMs
        self.parallel = parallel
    }
}
