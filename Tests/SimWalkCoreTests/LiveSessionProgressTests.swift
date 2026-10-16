//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// A live session's progress once the runner takes it over (SimWalk#83): `running` at the launch, each step counted with no total, and an end for every way the session stops.
struct LiveSessionProgressTests {
    /// The runner's `running` keeps the session `start` began; each step moves the current step on, a read moves nothing, and `end` writes `done`.
    @Test
    func stepsAdvanceTheIndexAndEndWritesDone() throws {
        let directory = try TemporaryDirectory()
        let session = try Self.session(in: directory)
        _ = try session.channel.send(.step, step: .tap(label: "Next"))
        _ = try session.channel.send(.read)
        _ = try session.channel.send(.step, step: .back)
        _ = try session.channel.send(.end)
        let script = LiveSessionLoopTests.Script()
        var seen: [String: WalkProgress] = [:]

        let exit = Self.loop(session, idle: 900).run(
            heartbeat: script.heartbeat(on: session.channel),
            start: script.start,
            answer: { request in
                seen["\(request.action.rawValue) \(request.n)"] = try ProgressWriterTests.read(session.url)
                return try script.answer(request)
            },
            handBack: script.handBack,
            now: script.now,
            pause: script.pause
        )
        let ended = try ProgressWriterTests.read(session.url)

        #expect(exit.reason == .ended)
        #expect(seen["step 1"]?.phase == .running)
        #expect(seen["step 1"]?.currentStep == WalkProgress.CurrentStep(index: 1, action: "tap 'Next'"))
        #expect(seen["read 2"]?.currentStep?.index == 1)
        #expect(seen["step 3"]?.currentStep == WalkProgress.CurrentStep(index: 2, action: "back"))
        #expect(ended.phase == .done)
        #expect(ended.error == nil)
        #expect(ended.tool == "session")
        #expect(ended.pid == Self.runnerPID)
        #expect(ended.currentStep?.total == nil)
    }

    /// A `type` step's progress names the field and not the text, which may be a password: a status line puts the file on screen (SimWalk#90).
    @Test
    func aTypeStepsProgressCarriesNoText() throws {
        let directory = try TemporaryDirectory()
        let session = try Self.session(in: directory)
        _ = try session.channel.send(.step, step: .type(label: "Password", text: "hunter2"))
        _ = try session.channel.send(.end)
        let script = LiveSessionLoopTests.Script()
        var written: Data?

        _ = Self.loop(session, idle: 900).run(
            heartbeat: script.heartbeat(on: session.channel),
            start: script.start,
            answer: { request in
                if request.action == .step {
                    written = try Data(contentsOf: session.url)
                }
                return try script.answer(request)
            },
            handBack: script.handBack,
            now: script.now,
            pause: script.pause
        )
        let bytes = try #require(written)
        let progress = try WalkProgress.decoder().decode(WalkProgress.self, from: bytes)

        #expect(progress.currentStep == WalkProgress.CurrentStep(index: 1, action: "type into 'Password'"))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("hunter2"))
    }

    /// An `openURL` step's progress line keeps an http(s) URL's scheme and host and drops userinfo, port, path, query and fragment, where a token can sit (SimWalk#91); any other scheme, whose host can be the token, keeps its scheme alone, and one with no scheme shows nothing of itself.
    @Test(arguments: [
        ("myapp://settings/account?token=abc123#frag", "openURL 'myapp:…'"),
        ("myapp://3f9a1c-reset-token", "openURL 'myapp:…'"),
        ("HTTPS://example.com/a", "openURL 'HTTPS://example.com/…'"),
        ("https://user:s3cret@example.com/path", "openURL 'https://example.com/…'"),
        ("https://example.com:8443", "openURL 'https://example.com/…'"),
        ("https://example.com", "openURL 'https://example.com'"),
        ("mailto:me@example.com?subject=abc123", "openURL 'mailto:…'"),
        ("myapp:token-abc123", "openURL 'myapp:…'"),
        ("abc123-not-a-url", "openURL '…'"),
    ])
    func anOpenURLStepsProgressLineDropsWhatCanHoldASecret(url: String, line: String) {
        let progressLine = Walkbook.RouteStep.openURL(url: url).progressLine

        #expect(progressLine == line)
        #expect(!progressLine.contains("abc123"))
        #expect(!progressLine.contains("s3cret"))
    }

    /// A session nobody uses for its whole timeout stopped as designed: `done`.
    @Test
    func anIdleSessionEndsDone() throws {
        let directory = try TemporaryDirectory()
        let session = try Self.session(in: directory)
        let script = LiveSessionLoopTests.Script()

        let exit = Self.loop(session, idle: 3).run(heartbeat: script.heartbeat(on: session.channel), start: script.start, answer: script.answer, handBack: script.handBack, now: script.now, pause: script.pause)
        let ended = try ProgressWriterTests.read(session.url)

        #expect(exit.reason == .idle)
        #expect(ended.phase == .done)
    }

    /// A launch that fails ends the file `failed` in the exit record's words.
    @Test
    func aFailedLaunchEndsFailedWithTheExitDetail() throws {
        let directory = try TemporaryDirectory()
        let session = try Self.session(in: directory)
        let script = LiveSessionLoopTests.Script(failingStart: true)

        let exit = Self.loop(session, idle: 900).run(heartbeat: script.heartbeat(on: session.channel), start: script.start, answer: script.answer, handBack: script.handBack, now: script.now, pause: script.pause)
        let ended = try ProgressWriterTests.read(session.url)

        #expect(exit.reason == .failed)
        #expect(ended.phase == .failed)
        #expect(ended.error == "the launch failed")
    }

    /// A start cancelled before the runner took the file over stays cancelled through the runner's `running`, its steps and its end.
    @Test
    func aStartCancelledBeforeTheHandOverStaysCancelled() throws {
        let directory = try TemporaryDirectory()
        let session = try Self.session(in: directory, cancelled: true)
        _ = try session.channel.send(.step, step: .back)
        _ = try session.channel.send(.end)
        let script = LiveSessionLoopTests.Script()

        _ = Self.loop(session, idle: 900).run(heartbeat: script.heartbeat(on: session.channel), start: script.start, answer: script.answer, handBack: script.handBack, now: script.now, pause: script.pause)
        let ended = try ProgressWriterTests.read(session.url)

        #expect(ended.phase == .failed)
        #expect(ended.error == "cancelled")
    }

    /// The host names the runner's pid after the spawn, which can land after the runner adopted the file: the runner reads the file again before `running`, so its writes carry the host's pid rather than the one it adopted.
    @Test
    func theRunnersRunningCarriesAPidTheHostWroteAfterTheAdoption() throws {
        let directory = try TemporaryDirectory()
        let session = try Self.session(in: directory, runnerPID: nil)
        let progress = ProgressWriter.adopting(url: session.url)
        session.host.commit { $0.pid = Self.runnerPID }
        _ = try session.channel.send(.read)
        _ = try session.channel.send(.end)
        let script = LiveSessionLoopTests.Script()
        var running: WalkProgress?

        _ = LiveSessionLoop(channel: session.channel, idle: LiveSessionIdle(timeout: 900), progress: progress).run(
            heartbeat: script.heartbeat(on: session.channel),
            start: script.start,
            answer: { request in
                running = try ProgressWriterTests.read(session.url)
                return try script.answer(request)
            },
            handBack: script.handBack,
            now: script.now,
            pause: script.pause
        )

        #expect(running?.phase == .running)
        #expect(running?.pid == Self.runnerPID)
    }

    private static let runnerPID: Int32 = 4242

    /// A session's directory and the progress file its host began, in `launching` with `runnerPID` when there is one, cancelled when `cancelled`.
    private static func session(in directory: TemporaryDirectory, runnerPID: Int32? = runnerPID, cancelled: Bool = false) throws -> Session {
        let channel = LiveSessionChannel(layout: LiveSessionLayout(directory: directory.url.appendingPathComponent("session", isDirectory: true)))
        try channel.prepare()
        try channel.writeLaunch(LiveSessionLaunch(appBundleID: "app.example", state: nil))
        let url = directory.url.appendingPathComponent("s.json")
        let host = ProgressWriter(url: url, clock: { Date() }, pid: 1)
        host.begin(tool: "session", phase: .building)
        host.commit { progress in
            progress.phase = .launching
            progress.pid = runnerPID ?? progress.pid
        }
        if cancelled {
            host.cancel()
        }
        return Session(channel: channel, url: url, host: host)
    }

    private static func loop(_ session: Session, idle timeout: TimeInterval) -> LiveSessionLoop {
        LiveSessionLoop(channel: session.channel, idle: LiveSessionIdle(timeout: timeout), progress: ProgressWriter.adopting(url: session.url))
    }
}

private extension LiveSessionProgressTests {
    /// A session's channel, its progress file, and the host's writer of that file.
    struct Session {
        let channel: LiveSessionChannel
        let url: URL
        let host: ProgressWriter
    }
}
