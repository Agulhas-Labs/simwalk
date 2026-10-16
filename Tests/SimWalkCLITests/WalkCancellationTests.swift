//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import SimWalkMCP
import SimWalkTestSupport
import Testing

/// A cancelled walk ends its progress file `failed` / `cancelled` on both faces (SimWalk#83) — an MCP client's `notifications/cancelled`, and a SIGTERM or SIGINT to the CLI.
struct WalkCancellationTests {
    /// The cancel is heard while the walk holds the server; the file says `cancelled` while the walk still runs and still says it after the walk ends its own way, and the call is never answered while the server goes on answering.
    ///
    /// The walk is held after its `begin` by a runner that resolves only when the test lets it, then fails — so it stays alive in `booting` for as long as the test needs, with no simulator involved.
    @Test
    func anMCPCancelEndsTheWalksFileCancelledAndTheCallGoesUnanswered() async throws {
        let directory = try TemporaryDirectory()
        let walkbook = directory.url.appendingPathComponent("smoke.json")
        try Data(Self.walkbook.utf8).write(to: walkbook)
        let environment = ["SIMWALK_USAGE_LOG": directory.url.appendingPathComponent("usage.jsonl").path, "CLAUDE_CODE_SESSION_ID": "cancel"]
        let progress = ProgressLocation.progressURL(session: "cancel", in: directory.url)
        let gate = DispatchSemaphore(value: 0)
        let root = directory.url
        let input = Pipe()
        let output = Pipe()
        let server = SimWalkMCPServer(
            input: input.fileHandleForReading,
            output: output.fileHandleForWriting,
            log: { _ in },
            usage: nil,
            session: nil,
            answering: { _, arguments, cancellation in
                let command = try WalkCommand.parse(arguments)
                return try command.performWalk(
                    runner: {
                        gate.wait()
                        throw Held()
                    },
                    builds: RunnerBuilds(directory: root.appendingPathComponent("runner-builds", isDirectory: true)),
                    leases: LeaseStore(directory: root.appendingPathComponent("leases", isDirectory: true), isAlive: { _ in true }),
                    telemetry: command.telemetry(environment: environment, cancellation: cancellation)
                ).servedAnswer()
            }
        )
        let serving = Task { await server.run() }
        let arguments = ["walkbook": walkbook.path, "output": directory.url.appendingPathComponent("out.simwalk").path]

        try Self.send(["jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": ["name": "walk", "arguments": arguments]], to: input)
        let booted = await Self.poll(progress) { $0.phase == .booting }
        try Self.send(["jsonrpc": "2.0", "method": "notifications/cancelled", "params": ["requestId": 7, "reason": "test"]], to: input)
        let cancelledWhileRunning = await Self.poll(progress) { $0.error == "cancelled" }
        gate.signal()
        try Self.send(["jsonrpc": "2.0", "id": 8, "method": "ping"], to: input)
        try input.fileHandleForWriting.close()
        await serving.value
        try output.fileHandleForWriting.close()
        let written = try output.fileHandleForReading.readToEnd() ?? Data()
        let responses = try written.split(separator: 0x0A).map { try JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] }
        let ended = try Self.read(progress)

        #expect(booted)
        #expect(cancelledWhileRunning)
        #expect(ended.phase == .failed)
        #expect(ended.error == "cancelled")
        #expect(responses.map { $0?["id"] as? Int } == [8])
    }

    /// The signal's work is done off its handler: the run is cancelled first, then the signal is sent again with its default action back — read at the moment it is sent, since a real process sending it into the no-op handler would never end.
    ///
    /// SIGIO stands in for SIGTERM and SIGINT, and the test's `end` for the `kill(2)` that ends a real process. Its default action is to discard it: a SIGUSR2 here once ended the test process, the signal apparently delivered after the default action was back, so a signal that terminates by default is not safe to send. Each signal test has a signal of its own: the suite's tests share one process and run at once.
    @Test
    func aSignalCancelsTheRunBeforeItIsSentAgain() async {
        let cancellation = Cancellation()
        let order = Order()
        cancellation.onCancel { order.append("cancel") }
        let signals = TerminationSignals(cancelling: cancellation, signals: [SIGIO]) { number in
            order.append("end \(number), \(TerminationSignals.disposition(of: number) == 0 ? "default" : "still caught")")
        }

        kill(getpid(), SIGIO)
        let heard = await Self.poll { order.steps.count == 2 }
        withExtendedLifetime(signals) {}

        #expect(heard)
        #expect(order.steps == ["cancel", "end \(SIGIO), default"])
    }

    /// A signal the caller set to `SIG_IGN` (`trap '' INT`) is left ignored and cancels nothing, while a signal beside it that was not ignored is still heard.
    ///
    /// SIGWINCH and SIGURG, whose default action is to do nothing, so no outcome of this test can end the test process.
    @Test
    func aSignalTheCallerIgnoresStaysIgnoredAndCancelsNothing() async {
        var ignore = sigaction()
        ignore.__sigaction_u.__sa_handler = SIG_IGN
        var before = sigaction()
        sigaction(SIGWINCH, &ignore, &before)
        defer { sigaction(SIGWINCH, &before, nil) }
        let cancellation = Cancellation()
        let order = Order()
        cancellation.onCancel { order.append("cancel") }
        let signals = TerminationSignals(cancelling: cancellation, signals: [SIGWINCH, SIGURG]) { number in order.append("end \(number)") }

        let stillIgnored = TerminationSignals.isIgnored(SIGWINCH)
        kill(getpid(), SIGWINCH)
        kill(getpid(), SIGURG)
        let heard = await Self.poll { order.steps.contains("end \(SIGURG)") }
        withExtendedLifetime(signals) {}

        #expect(stillIgnored)
        #expect(heard)
        #expect(order.steps == ["cancel", "end \(SIGURG)"])
    }

    /// Once the object goes away, each signal has the action it had before, so a signal after the walk is not swallowed by a handler nothing listens behind.
    ///
    /// SIGINFO, set to a handler of the test's own first, so that what comes back is shown to be what was there rather than the default.
    @Test
    func releasingTheSignalsPutsBackTheActionItFound() {
        var marked = sigaction()
        marked.__sigaction_u.__sa_handler = Self.marker
        var before = sigaction()
        sigaction(SIGINFO, &marked, &before)
        defer { sigaction(SIGINFO, &before, nil) }
        let marker = TerminationSignals.disposition(Self.marker)

        let whileHeld: Int
        do {
            let signals = TerminationSignals(cancelling: Cancellation(), signals: [SIGINFO]) { _ in }
            whileHeld = TerminationSignals.disposition(of: SIGINFO)
            withExtendedLifetime(signals) {}
        }
        let afterwards = TerminationSignals.disposition(of: SIGINFO)

        #expect(whileHeld != marker)
        #expect(afterwards == marker)
    }
}

extension WalkCancellationTests {
    /// The runner a held walk resolves once the test lets it, by failing.
    struct Held: Error {}

    /// A handler of the test's own, told apart from `SIG_DFL` and `SIG_IGN` by its address.
    static let marker: @convention(c) (Int32) -> Void = { _ in }

    /// The steps a signal's handling took, in order.
    final class Order: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [String] = []

        var steps: [String] {
            lock.withLock { recorded }
        }

        func append(_ step: String) {
            lock.withLock { recorded.append(step) }
        }
    }

    static var walkbook: String {
        """
        {
          "name": "smoke",
          "appBundleID": "com.example.app",
          "screens": [
            { "id": "today", "route": [{ "tab": { "label": "Today" } }], "states": [{ "theme": "light" }] }
          ]
        }
        """
    }

    static func send(_ message: [String: Any], to input: Pipe) throws {
        var line = try JSONSerialization.data(withJSONObject: message)
        line.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: line)
    }

    static func read(_ url: URL) throws -> WalkProgress {
        try WalkProgress.decoder().decode(WalkProgress.self, from: Data(contentsOf: url))
    }

    /// Whether the file at `url` came to satisfy `condition` within 20 s.
    static func poll(_ url: URL, until condition: @escaping (WalkProgress) -> Bool) async -> Bool {
        await poll { (try? read(url)).map(condition) ?? false }
    }

    /// Whether `condition` came to hold within 20 s.
    static func poll(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(20)
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
}
