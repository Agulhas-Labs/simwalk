//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// The file channel a live session's host and resident runner share: a request or response is read whole or not at all, numbers are claimed once each, and a wait always ends.
struct LiveSessionChannelTests {
    /// A write still in its temporary file is not a request; the renamed file is, whole, and nothing temporary is left behind.
    @Test
    func arequestIsSeenWholeOrNotAtAll() throws {
        let directory = try TemporaryDirectory()
        let channel = try Self.channel(in: directory)
        try Data("{\"n\": 1, \"act".utf8).write(to: channel.layout.requests.appendingPathComponent(".1.json.partial.tmp"))
        let unsent = try channel.request(1)
        let number = try channel.send(.read)
        let names = try FileManager.default.contentsOfDirectory(atPath: channel.layout.requests.path)

        #expect(unsent == nil)
        #expect(number == 1)
        #expect(try channel.request(1) == LiveSessionRequest(n: 1, action: .read))
        #expect(names.filter { $0.hasSuffix(".tmp") } == [".1.json.partial.tmp"])
    }

    /// Hosts sending at once each claim a number of their own, and together they number the session without a gap.
    @Test
    func concurrentSendsClaimDistinctConsecutiveNumbers() throws {
        let directory = try TemporaryDirectory()
        let channel = try Self.channel(in: directory)
        let numbers = Numbers()

        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            numbers.add(Result { try channel.send(.read) })
        }

        #expect(numbers.sorted == Array(1 ... 16))
        #expect(channel.layout.requestNumbers() == Array(1 ... 16))
    }

    /// A response is found under its request's number, and the runner reads requests in the order they were sent.
    @Test
    func aresponseIsFoundUnderItsRequestsNumber() throws {
        let directory = try TemporaryDirectory()
        let channel = try Self.channel(in: directory)
        let first = try channel.send(.read)
        let second = try channel.send(.end)
        try channel.respond(LiveSessionResponse(n: second, action: .end))

        #expect(try channel.request(first)?.action == .read)
        #expect(try channel.request(second)?.action == .end)
        #expect(try channel.response(to: first) == nil)
        #expect(try channel.response(to: second) == LiveSessionResponse(n: 2, action: .end))
    }

    /// Asking after a request never sent is refused at once, rather than waited on until the timeout.
    @Test
    func aresponseToARequestNeverSentIsRefused() throws {
        let directory = try TemporaryDirectory()
        let channel = try Self.channel(in: directory)
        var pauses = 0

        #expect(throws: LiveSessionError.noSuchRequest(number: 3, path: channel.layout.request(3).path)) {
            try channel.awaitResponse(to: 3, timeout: 60, isRunnerAlive: { true }, pause: { _ in pauses += 1 }, now: { Self.start })
        }
        #expect(pauses == 0)
    }

    /// A response filed under one number that says it answers another is refused rather than served as this one's.
    @Test
    func aresponseNumberedOtherThanItsFileIsRefused() throws {
        let directory = try TemporaryDirectory()
        let channel = try Self.channel(in: directory)
        _ = try channel.send(.read)
        _ = try LiveSessionChannel.write(CaptureBundle.encoder().encode(LiveSessionResponse(n: 7, action: .read)), to: channel.layout.response(1), exclusively: false)

        #expect(throws: LiveSessionError.self) {
            try channel.response(to: 1)
        }
    }

    /// A runner that stopped on its own idle timeout ends the host's wait with the reason it wrote, not a timeout of the host's.
    @Test
    func therunnersIdleExitIsWhatTheHostReports() throws {
        let directory = try TemporaryDirectory()
        let channel = try Self.channel(in: directory)
        let number = try channel.send(.read)
        let exit = LiveSessionExit.idle(after: LiveSessionIdle.standardTimeout, served: 2, stoppedAt: Self.start)
        try channel.markExit(exit)

        #expect(throws: LiveSessionError.runnerExited(number: number, exit: exit)) {
            try channel.awaitResponse(to: number, timeout: 60, isRunnerAlive: { true }, pause: { _ in }, now: { Self.start })
        }
        #expect(try channel.exitRecord()?.summary == "exited on its own: no request for 15 min (2 served)")
    }

    /// A runner still alive that never answers ends the wait at its timeout.
    @Test
    func awaitEndsAtItsTimeoutWhenTheRunnerNeverAnswers() throws {
        let directory = try TemporaryDirectory()
        let channel = try Self.channel(in: directory)
        let number = try channel.send(.read)
        var clock = Self.start

        #expect(throws: LiveSessionError.noResponse(number: number, waited: 1)) {
            try channel.awaitResponse(to: number, timeout: 1, isRunnerAlive: { true }, pause: { clock += $0 }, now: { clock })
        }
    }

    /// The idle decision: expired at the timeout and not before, and an override that states no positive number is the standard fifteen minutes.
    @Test
    func theidleTimeoutExpiresAtItsLengthAndAnOverrideShortensIt() {
        let idle = LiveSessionIdle(timeout: LiveSessionIdle.timeout(fromOverride: "20"))

        #expect(idle.hasExpired(lastRequest: Self.start, now: Self.start.addingTimeInterval(19.9)) == false)
        #expect(idle.hasExpired(lastRequest: Self.start, now: Self.start.addingTimeInterval(20)))
        #expect(LiveSessionIdle.timeout(fromOverride: nil) == 900)
        #expect(LiveSessionIdle.timeout(fromOverride: "-5") == 900)
    }

    private static let start = Date(timeIntervalSince1970: 1_000_000)

    private static func channel(in directory: TemporaryDirectory) throws -> LiveSessionChannel {
        let channel = LiveSessionChannel(layout: LiveSessionLayout(directory: directory.url.appendingPathComponent("session", isDirectory: true)))
        try channel.prepare()
        return channel
    }
}

extension LiveSessionChannelTests {
    /// The numbers concurrent sends claimed.
    final class Numbers: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed: [Int] = []

        var sorted: [Int] {
            lock.withLock { claimed.sorted() }
        }

        func add(_ result: Result<Int, Error>) {
            guard case let .success(number) = result else { return }
            lock.withLock { claimed.append(number) }
        }
    }
}
