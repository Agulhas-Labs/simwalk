//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import SimWalkDriver

/// What a walk or a dry run writes about itself while it runs: the progress file's phases and the timings of each segment (`Docs/SIMWALK-PROGRESS.md` §2, §3).
///
/// **The host owns the timings.** The runner writes the file between `launching` and `matching`, and the host takes it back with ``ProgressWriter/reload()``; the summary is stamped again from this object's own ``timings`` in the same write, so nothing the runner wrote can overwrite them. Timed on a monotonic clock — the wall clock can step while a boot takes thirty seconds.
final class WalkTelemetry {
    let writer: ProgressWriter
    /// Where a walk's result file goes; `nil` writes none.
    ///
    /// A dry run writes none either way.
    let resultURL: URL?
    /// Whether the result is written whole — every step's states and route, uncapped — rather than compact (§4).
    let verbose: Bool
    private(set) var timings = PhaseTimings()
    /// Writes `failed` if this object goes away before the run ended — a backstop, not how a run ends.
    private let run: ProgressRun
    private let clock: () -> TimeInterval
    private var startedAt: TimeInterval?
    /// What ends the run as `failed` / `cancelled` from outside it — an MCP client's cancel, a signal to the CLI — heard from ``begin(tool:)`` on.
    private let cancellation: Cancellation?

    /// `claim`, when given, is held by the run's backstop, so it is released only after a run going away unfinished has written its end.
    init(
        writer: ProgressWriter,
        resultURL: URL?,
        verbose: Bool = false,
        claim: ProgressClaim? = nil,
        cancellation: Cancellation? = nil,
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.writer = writer
        self.resultURL = resultURL
        self.verbose = verbose
        self.clock = clock
        self.cancellation = cancellation
        run = ProgressRun(writer: writer, claim: claim)
    }

    /// Starts the run in `booting`, naming the usage log (`logPath`) in that first write — the result carries the same path once it ends — replacing whatever the file held — and from here a cancel ends it, one that came before included: registered after the begin, since a writer that has not begun has no run to end.
    ///
    /// Begun once: a second call is ignored, so the MCP face can begin before the target is resolved and the walk's own `begin` in `prepare` leaves the run, and its `startedAt`, as they are.
    func begin(tool: String, logPath: String? = nil) {
        guard startedAt == nil else { return }
        startedAt = clock()
        timings = PhaseTimings()
        writer.begin(tool: tool, logPath: logPath)
        cancellation?.onCancel { [writer] in writer.cancel() }
    }

    /// The screens the run executes, once the walkbook is loaded; `nil` leaves both counts out (a `--screens` refusal comes later).
    ///
    /// The step index is `0` until the runner starts its first screen and writes its own.
    func plan(screens: Int?) {
        guard let screens else { return }
        writer.commit { progress in
            progress.matches = WalkProgress.Matches(planned: screens)
            progress.currentStep = WalkProgress.CurrentStep(index: 0, total: screens)
        }
    }

    /// The physical device a device walk runs on, recorded as one so a poll knows the walk keeps no result file (SimWalk#152).
    func resolved(_ device: PhysicalDevice) {
        writer.commit { progress in
            progress.device = WalkProgress.Device(name: device.name, udid: device.udid, osVersion: device.osVersion, physical: true)
        }
    }

    /// The device the run resolved and the app it walks.
    func resolved(_ simulator: Simulator, app: String) {
        writer.commit { progress in
            progress.device = WalkProgress.Device(name: simulator.name, udid: simulator.udid, osVersion: simulator.osVersion)
            progress.app = app
        }
    }

    /// Moves the run to `phase`.
    func enter(_ phase: WalkProgress.Phase) {
        writer.commit { $0.phase = phase }
    }

    /// Runs `body` in `phase`, timing it into `segment`; the summary is written as the segment ends.
    func timed<T>(_ phase: WalkProgress.Phase, _ segment: WritableKeyPath<PhaseTimings, Int?>, _ body: () throws -> T) rethrows -> T {
        enter(phase)
        return try measured(segment, runnerOwnsFile: false, body)
    }

    /// Times `body` into `segment` without changing the phase — the runner's walk, whose phases the runner writes.
    func measured<T>(_ segment: WritableKeyPath<PhaseTimings, Int?>, runnerOwnsFile: Bool = true, _ body: () throws -> T) rethrows -> T {
        let start = clock()
        defer {
            timings[keyPath: segment] = Self.milliseconds(clock() - start)
            // Read back first, when the runner wrote while `body` ran: the host's copy of the file is then older. A segment only the host writes during reads nothing, so a run sharing the file cannot leak into this one.
            if runnerOwnsFile {
                writer.reload()
            }
            writer.commit { [timings] in $0.summary = timings }
        }
        return try body()
    }

    /// Takes the run back from the runner: the file read back, the host's timings stamped over whatever the runner left, and the phase `matching`.
    func takeBack() {
        writer.reload()
        writer.commit { [timings] progress in
            progress.summary = timings
            progress.phase = .matching
        }
    }

    /// Ends a walk with its result, built from the bundle it answered with: `done` when every screen passed, else `failed`.
    func finish(walk bundle: CaptureBundle, logPath: String?) {
        stampTotal()
        let result = WalkResultBuilder(tool: writer.current.tool).build(manifest: bundle.manifest, bundleURL: bundle.url, timings: timings, logPath: logPath, verbose: verbose)
        let ending: ProgressWriter.Ending = result.verdict == .passed ? .done : .failed
        // The final bundle is the truth: an appearance retry can fold a screen the first pass refused, which the runner's counts never saw.
        writer.commit { [timings, counts = result.counts] in
            $0.summary = timings
            var matches = WalkProgress.Matches(planned: counts.planned)
            matches.passed = counts.passed
            matches.failed = counts.failed
            matches.pending = 0
            $0.matches = matches
        }
        guard let resultURL else {
            writer.finish(ending)
            return
        }
        writer.finish(writing: result, to: resultURL, as: ending)
    }

    /// Ends a dry run, which writes no result: `failed` when a route drifted, else `done`.
    func finish(dryRun report: RouteProbeReport) {
        stampTotal()
        writer.commit { [timings] in $0.summary = timings }
        writer.finish(report.drifted.isEmpty ? .done : .failed)
    }

    /// Ends the run as `failed` with the text of what escaped it.
    func fail(_ error: Error) {
        stampTotal()
        writer.commit { [timings] in $0.summary = timings }
        writer.finish(.failed, error: String(describing: error))
    }

    /// `body`, with anything it throws ending `telemetry`'s run as `failed` before it is rethrown; `nil` telemetry runs `body` alone.
    static func recording<T>(on telemetry: WalkTelemetry?, _ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch {
            telemetry?.fail(error)
            throw error
        }
    }

    /// `body`, with anything it throws ending the run as `failed` unless something has ended it already.
    static func recordingUnended<T>(on telemetry: WalkTelemetry, _ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch {
            if !telemetry.writer.current.phase.isTerminal {
                telemetry.fail(error)
            }
            throw error
        }
    }

    /// Ends a run that nothing ended — a physical device's walk, which writes no result — `done` when its answer is unqualified, else `failed`.
    func endUnended(by answer: Answer) {
        guard !writer.current.phase.isTerminal else { return }
        stampTotal()
        writer.commit { [timings] in $0.summary = timings }
        guard case .unqualified = answer.verdict else {
            return writer.finish(.failed, error: answer.verdict.line)
        }
        writer.finish(.done)
    }

    /// `body` in `phase`, timed into `segment`, when the run is watched; `body` alone when it is not.
    static func segment(_ telemetry: WalkTelemetry?, _ phase: WalkProgress.Phase, _ segment: WritableKeyPath<PhaseTimings, Int?>, _ body: () throws -> Void) rethrows {
        guard let telemetry else { return try body() }
        try telemetry.timed(phase, segment, body)
    }

    /// `body` timed into `segment` with the phase left as it is, when the run is watched (`runnerOwnsFile: false` when no runner writes the file, as in a dry run); `body` alone when it is not.
    static func measure(_ telemetry: WalkTelemetry?, _ segment: WritableKeyPath<PhaseTimings, Int?>, runnerOwnsFile: Bool = true, _ body: () throws -> Void) rethrows {
        guard let telemetry else { return try body() }
        try telemetry.measured(segment, runnerOwnsFile: runnerOwnsFile, body)
    }

    /// Milliseconds since ``begin(tool:logPath:)`` on the clock `totalMs` is read from, so a mark taken here is never past the total; `nil` before the begin.
    ///
    /// Read by every shard of a parallel walk at once: `startedAt` is only written by the begin, before they start, and the clock is a read of the system's.
    func elapsedMilliseconds() -> Int? {
        startedAt.map { Self.milliseconds(clock() - $0) }
    }

    /// Stamps a parallel walk's breakdown into the timings, for ``finish(walk:logPath:)`` to carry into the result.
    func recordParallel(_ parallel: ParallelTimings) {
        timings.parallel = parallel
    }

    private func stampTotal() {
        timings.totalMs = startedAt.map { Self.milliseconds(clock() - $0) }
    }

    private static func milliseconds(_ interval: TimeInterval) -> Int {
        Int((interval * 1000).rounded())
    }
}
