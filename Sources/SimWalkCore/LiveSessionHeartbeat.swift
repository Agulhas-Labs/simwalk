//
// Copyright © Agulhas Labs
//

import Foundation

/// A live session runner's proof of life (`heartbeat.json`): when it was written, and the interval within which the runner promises to write it again.
///
/// **It bounds a silent stop from above** (SimWalk#91 item 10, `Docs/SIMWALK-PROGRESS.md` §3). A runner that crashed or was killed writes no `exit.json`, and the session directory's last write bounds its stop only from below, so `session list` used to give such a session the teardown's whole wait from now, qualified, however long ago it died (SimWalk#76). A runner that was still beating at ``writtenAt`` stopped no later than ``latestStop``, and the host waits from there as it would from `exit.json`'s stop time.
///
/// **The bound holds only while the timer is on time to within two intervals.** A runner starved of the CPU for longer than that and then killed before its next beat stopped after it; the tolerance is fixed, because a heartbeat cannot prove its own punctuality. The likeliest way to be late is the Mac sleeping: the timer runs on `DispatchTime`, which stops during sleep, while `at` is the wall clock, so a runner killed in the seconds after a wake, before its next beat, has a bound as early as the sleep was long. An idle session is not exposed (its idle check writes `exit.json` first); one stuck in a step is. Otherwise the runner and the host read the same Mac's clock, so clocks are not a second error.
public struct LiveSessionHeartbeat: Codable, Equatable, Sendable {
    /// When the runner wrote it, by its clock (`at` in the file).
    public let writtenAt: Date
    /// The seconds within which the runner promises to write it again.
    public let interval: TimeInterval

    public init(writtenAt: Date, interval: TimeInterval = Self.interval) {
        self.writtenAt = writtenAt
        self.interval = interval
    }

    /// The latest the runner can have stopped, given it wrote this: ``writtenAt`` plus three intervals — the one it promised, and two of tolerance for a timer that fired late.
    public var latestStop: Date {
        writtenAt.addingTimeInterval(Self.intervalsToStop * interval)
    }

    /// How often the runner beats, in seconds: often enough that a dead session's bound is a few seconds after its death, rarely enough that the writes are noise.
    public static var interval: TimeInterval {
        2
    }

    /// How many intervals after a beat the stop is bounded by.
    static var intervalsToStop: Double {
        3
    }
}

extension LiveSessionHeartbeat {
    /// The file's own keys: `at` is the protocol's name, kept short in a file written every two seconds.
    enum CodingKeys: String, CodingKey {
        case writtenAt = "at"
        case interval
    }
}

public extension LiveSessionHeartbeat {
    /// Starts beating on `channel`: the first beat now, on the calling thread, so it is down before whatever the caller does next — the runner calls this before it launches the app, so a crash in the launch is bounded too — then one every `interval` from `schedule`.
    ///
    /// A beat that cannot be written removes the file rather than leaving the last one standing: a stale beat bounds the stop too early, which records `.alreadyOn` over a teardown still to come, while no file at all is only today's longer, qualified wait.
    ///
    /// - Parameters:
    ///   - now: the clock each beat is stamped with.
    ///   - schedule: calls its closure every interval until the closure it returns is called, and calls it no more once that returns — ``backgroundTimer(every:_:)`` in use, a script in a test.
    static func start(
        on channel: LiveSessionChannel,
        interval: TimeInterval = Self.interval,
        now: @escaping @Sendable () -> Date = { Date() },
        schedule: (TimeInterval, @escaping @Sendable () -> Void) -> @Sendable () -> Void = backgroundTimer
    ) -> Running {
        let beat: @Sendable () -> Void = {
            do {
                try channel.markHeartbeat(LiveSessionHeartbeat(writtenAt: now(), interval: interval))
            } catch {
                try? FileManager.default.removeItem(at: channel.layout.heartbeat)
            }
        }
        beat()
        return Running(stop: schedule(interval, beat))
    }

    /// Calls `beat` every `interval` on a serial queue of its own, never the main thread — an XCUITest query blocks that for as long as a step takes, which is the very stop a heartbeat has to bound — until the closure it returns is called.
    ///
    /// The returned closure cancels on the timer's own queue, so no beat is still being written once it returns.
    ///
    /// **Only that closure stops it.** The handler holds the timer, so dropping every other reference leaves it beating — a dispatch timer nothing holds is freed and fires no more — and cancelling releases the handler and with it the timer. A loop that could not write `exit.json` leaves its heartbeat running, and the runner's `serve()` holds the ``Running`` only for the loop's call, so without this the beats would stop when that call returned rather than when the process died.
    static func backgroundTimer(every interval: TimeInterval, _ beat: @escaping @Sendable () -> Void) -> @Sendable () -> Void {
        let queue = DispatchQueue(label: "simwalk.session.heartbeat", qos: .userInitiated)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler { withExtendedLifetime(timer, beat) }
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(100))
        timer.resume()
        return { queue.sync { timer.cancel() } }
    }

    /// A heartbeat that is beating, minted only by ``start(on:interval:now:schedule:)`` (`init` is `fileprivate`).
    ///
    /// **`LiveSessionLoop.run` takes one**, and stops it once `exit.json` — which supersedes it — is written, and only then: a runner whose exit record could not be written beats on until its process dies. Starting the timer is the runner's own call, which no unit test reaches; requiring this proof of it means a runner that stops starting it stops compiling (the `SystemAlertCheck.Clearance` pattern).
    final class Running: LiveSessionLiveness, Sendable {
        private let cancel: @Sendable () -> Void

        fileprivate init(stop: @escaping @Sendable () -> Void) {
            cancel = stop
        }

        /// Stops the beats; none is written once this returns.
        ///
        /// Only the loop can call it, being the only holder of a ``LiveSessionExitRecorded``.
        public func stop(_: LiveSessionExitRecorded) {
            cancel()
        }
    }
}
