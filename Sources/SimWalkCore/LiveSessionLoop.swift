//
// Copyright © Agulhas Labs
//

import Foundation

/// The resident runner's side of a live session, from `launch.json` to `exit.json`: launch, mark ready, then serve requests strictly in number order until an `end`, the idle timeout, or a failure.
///
/// **Every way out writes the exit record** — `ended`, `idle`, or `failed` with the failure's own text — so a host reading a session whose runner is gone always finds why. The record supersedes the runner's heartbeat, so the loop stops the heartbeat once the record is down, and only then: a record that could not be written leaves the heartbeat beating until the process dies, so the bound it gives a host falls after everything that runs after the loop (an `XCTFail`, XCTest's teardown) rather than a few seconds after the loop returned. The device is handed back (``run(heartbeat:start:answer:handBack:now:pause:)``'s `handBack`) before each of them, and before an `end` is answered, so a host that has read the `end` response finds the device as it was.
///
/// **It writes the session's progress once the host hands it over** (`Docs/SIMWALK-PROGRESS.md` §3, SimWalk#83): `running` once the app is launched, each `step` request as the current step — counted from 1, with no total — and the end, `done` for an `end` or the idle timeout and `failed` with the exit record's detail otherwise. Reads change nothing in it.
///
/// The loop lives here rather than in the runner because `swift test` never compiles `Runner/`: which request comes next, when a session has gone idle, and what a request the runner cannot read gets back are decisions, and a decision in the runner is one nothing checks. The runner hands in only what it alone can do — launch the app and read it — and time arrives as a parameter.
///
/// **One loop for both targets** (SimWalk#116): a simulator's runner serves through the session directory (``LiveSessionLoop``), a device's through its socket (``DeviceSessionLoop``), and the transport's ``LiveSessionTransport/Liveness`` decides what `run` takes as its heartbeat.
public struct LiveSessionServingLoop<Transport: LiveSessionTransport> {
    public let transport: Transport
    public let idle: LiveSessionIdle
    /// The progress file `session start` began, adopted from it; `nil` writes none.
    public let progress: ProgressWriter?

    public init(transport: Transport, idle: LiveSessionIdle, progress: ProgressWriter? = nil) {
        self.transport = transport
        self.idle = idle
        self.progress = progress
    }

    /// Serves the session and returns the exit record it wrote.
    ///
    /// - Parameters:
    ///   - heartbeat: the runner's heartbeat, started before this so that it bounds a crash in the launch; stopped on every way out once the exit record is written, and left beating when it could not be. Taking it is what makes a simulator's runner start it: only ``LiveSessionHeartbeat/start(on:interval:now:schedule:)`` makes one. A device's runner has none, and says so with ``DeviceSessionTransport/NoHeartbeat/onDevice``.
    ///   - start: launches what `launch.json` names and says who is ready; a throw is the session's failure.
    ///   - answer: answers one request other than `end`; a throw is that request's failure, answered as one, and the session serves on.
    ///   - handBack: puts the device back as the host found it.
    ///   - pause: waits between polls of a transport that does not wait itself (``LiveSessionTransport/afterEmptyPoll(pause:)``).
    public func run(
        heartbeat: Transport.Liveness,
        start: (LiveSessionLaunch) throws -> LiveSessionReady,
        answer: (LiveSessionRequest) throws -> LiveSessionResponse,
        handBack: () -> Void,
        now: () -> Date,
        pause: (TimeInterval) -> Void
    ) -> LiveSessionExit {
        var served = 0
        var steps = 0
        do {
            let launch = try transport.launchRecord()
            let ready = try start(launch)
            // Read again rather than trusting the adoption: the host names the runner's pid after the spawn, which can land after the runner took the file over.
            progress?.reload()
            progress?.commit { $0.phase = .running }
            try transport.markReady(ready)
            var lastRequest = now()
            while true {
                let number = served + 1
                let request: LiveSessionRequest?
                do {
                    request = try transport.request(number)
                } catch {
                    // A request that is not one — an action this runner does not know, or a file of another
                    // shape — is answered as a failure under its number rather than guessed at or waited past.
                    try transport.respond(LiveSessionResponse(n: number, action: nil, failure: "\(error)"))
                    served = number
                    lastRequest = now()
                    continue
                }
                guard let request else {
                    if idle.hasExpired(lastRequest: lastRequest, now: now()) {
                        handBack()
                        return try record(.idle(after: idle.timeout, served: served, stoppedAt: now()), heartbeat: heartbeat)
                    }
                    transport.afterEmptyPoll(pause: pause)
                    continue
                }
                if request.action == .end {
                    handBack()
                }
                if request.action == .step {
                    steps += 1
                    progress?.commit { [steps] in $0.currentStep = WalkProgress.CurrentStep(index: steps, action: request.step?.progressLine) }
                }
                try transport.respond(Self.response(to: request, from: answer))
                served = number
                lastRequest = now()
                if request.action == .end {
                    return try record(LiveSessionExit(reason: .ended, detail: "sent end", served: served, stoppedAt: now()), heartbeat: heartbeat)
                }
            }
        } catch {
            handBack()
            let exit = LiveSessionExit(reason: .failed, detail: "\(error)", served: served, stoppedAt: now())
            finishProgress(exit)
            if (try? transport.markExit(exit)) != nil {
                heartbeat.stop(LiveSessionExitRecorded())
            }
            return exit
        }
    }

    /// Writes `exit` and then stops the heartbeat it supersedes; a write that throws leaves the heartbeat beating, for the failure path to try again.
    private func record(_ exit: LiveSessionExit, heartbeat: Transport.Liveness) throws -> LiveSessionExit {
        finishProgress(exit)
        try transport.markExit(exit)
        heartbeat.stop(LiveSessionExitRecorded())
        return exit
    }

    /// Ends the progress file as the session ended: `done` when it stopped as designed — sent `end`, or idle for its whole timeout — and `failed` with the exit record's detail when it could not serve.
    private func finishProgress(_ exit: LiveSessionExit) {
        switch exit.reason {
        case .ended, .idle:
            progress?.finish(.done)
        case .failed:
            progress?.finish(.failed, error: exit.detail)
        }
    }

    /// `answer`'s response, or the failure it threw, under the request's own number and action.
    private static func response(to request: LiveSessionRequest, from answer: (LiveSessionRequest) throws -> LiveSessionResponse) -> LiveSessionResponse {
        do {
            return try answer(request)
        } catch {
            return LiveSessionResponse(n: request.n, action: request.action, failure: "\(error)")
        }
    }
}

/// A simulator's live session loop, serving through the session directory.
public typealias LiveSessionLoop = LiveSessionServingLoop<LiveSessionChannel>

/// A physical device's live session loop, serving through the socket its runner listens on.
public typealias DeviceSessionLoop = LiveSessionServingLoop<DeviceSessionTransport>

public extension LiveSessionServingLoop where Transport == LiveSessionChannel {
    /// A loop serving the session directory `channel` names, as a simulator's runner does.
    init(channel: LiveSessionChannel, idle: LiveSessionIdle, progress: ProgressWriter? = nil) {
        self.init(transport: channel, idle: idle, progress: progress)
    }
}
