//
// Copyright © Agulhas Labs
//

import Foundation
import os
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// A device session's socket, served by the real loop on a thread of its own over loopback: the bind, the token, the numbering, and the connections that must not cost the session.
struct DeviceSessionTransportTests {
    /// Before the runner has bound, a hello is refused; once it has, the hello answers the ready record, and `end` is answered and recorded in `exit.json`.
    @Test
    func ahelloIsRefusedUntilTheRunnerBindsThenAnswersTheReadyRecord() throws {
        try Self.onFreePort { port in
            let container = try TemporaryDirectory()
            let served = ServedSession.start(container: container.url)
            let client = Self.client(port: port)

            #expect(throws: DeviceSessionClientError.refused) { try client.hello() }
            try Self.writeBind(Self.bind(port: port), in: container.url)
            let ready = try Self.awaitReady(client, served: served)
            let end = try client.exchange(DeviceSessionRequest(action: .end), timeout: 5)
            let exit = try #require(served.exit(within: 5))

            #expect(ready == Self.ready)
            #expect(end == LiveSessionResponse(n: 1, action: .end))
            #expect(exit.reason == .ended)
            #expect(try Self.sameRecord(Self.writtenExit(in: container.url), exit))
            #expect(try Self.writtenExit(in: container.url)?.session == Self.session, "the record carries the session id the runner was launched with")
            #expect(!FileManager.default.fileExists(atPath: LiveSessionLayout(directory: container.url).bind.path))
        }
    }

    /// The runner numbers each request as it serves it — 1, then 2 — since a device request travels without a number.
    @Test
    func requestsAreNumberedByTheRunnerInServingOrder() throws {
        let session = try Self.readySession()
        let (container, client, served) = (session.container, session.client, session.served)

        let first = try client.exchange(DeviceSessionRequest(action: .read), timeout: 5)
        let second = try client.exchange(DeviceSessionRequest(action: .read), timeout: 5)
        _ = try client.exchange(DeviceSessionRequest(action: .end), timeout: 5)

        #expect(first == LiveSessionResponse(n: 1, action: .read))
        #expect(second == LiveSessionResponse(n: 2, action: .read))
        #expect(served.exit(within: 5)?.served == 3)
        withExtendedLifetime(container) {}
    }

    /// A frame with a wrong or missing token, or that is not JSON at all, is closed without a byte of answer and takes no number: the next good request is still 1.
    @Test
    func anunauthenticatedFrameIsClosedWithoutAByteAndTakesNoNumber() throws {
        let session = try Self.readySession()
        let (container, client, served) = (session.container, session.client, session.served)
        let wrong = try DeviceSessionToken.random()
        let frames = try [
            DeviceSessionFrame.encode(DeviceSessionFrame.Inbound(token: wrong, request: DeviceSessionRequest(action: .read))),
            Data("{\"request\": {\"action\": \"read\"}}\n".utf8),
            Data("not json\n".utf8),
        ]

        let replies = try frames.map { try client.rawExchange($0, timeout: 5) }
        let next = try client.exchange(DeviceSessionRequest(action: .read), timeout: 5)
        _ = try client.exchange(DeviceSessionRequest(action: .end), timeout: 5)

        #expect(replies == Array(repeating: .closed(Data()), count: 3))
        #expect(next.n == 1)
        #expect(served.exit(within: 5)?.served == 2)
        withExtendedLifetime(container) {}
    }

    /// An authenticated frame the runner cannot read — an action it does not know — is answered as a failure under its number, and the session serves on.
    @Test
    func anauthenticatedMalformedRequestIsAnsweredAsAFailureUnderItsNumber() throws {
        let session = try Self.readySession()
        let (container, client, served) = (session.container, session.client, session.served)
        let frame = Data("{\"token\": \"\(Self.token.hex)\", \"request\": {\"action\": \"fly\"}}\n".utf8)

        let reply = try client.rawExchange(frame, timeout: 5)
        let next = try client.exchange(DeviceSessionRequest(action: .read), timeout: 5)
        _ = try client.exchange(DeviceSessionRequest(action: .end), timeout: 5)
        guard case let .line(line) = reply else {
            Issue.record("the malformed request was not answered: \(reply)")
            return
        }
        let failure = try #require(try DeviceSessionFrame.decode(DeviceSessionFrame.Outbound.self, from: line).response)

        #expect(failure.n == 1)
        #expect(failure.action == nil)
        #expect(failure.failure?.contains("fly") == true)
        #expect(next.n == 2)
        #expect(served.exit(within: 5)?.reason == .ended)
        withExtendedLifetime(container) {}
    }

    /// A host that resets its connection before the answer is written costs neither the process nor the session: the write fails with `EPIPE` under `SO_NOSIGPIPE` instead of raising SIGPIPE, and the next request is served.
    @Test
    func ahostThatLeavesBeforeItsAnswerDoesNotKillTheRunner() throws {
        let hold = DispatchSemaphore(value: 0)
        let session = try Self.readySession { request in
            guard request.n == 1 else { return LiveSessionResponse(n: request.n, action: request.action) }
            hold.wait()
            // Large enough that the write meets the reset rather than fitting in a buffer before it.
            return LiveSessionResponse(n: request.n, action: request.action, failure: String(repeating: "x", count: 8 << 20))
        }
        let (container, client, served) = (session.container, session.client, session.served)
        let descriptor = try DeviceSessionSocket.connect(address: "::1", port: client.port, timeout: 5)
        _ = try DeviceSessionSocket.send(descriptor, DeviceSessionFrame.encode(DeviceSessionFrame.Inbound(token: Self.token, request: DeviceSessionRequest(action: .read))), timeout: 5)
        Thread.sleep(forTimeInterval: 0.2)
        var reset = linger(l_onoff: 1, l_linger: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_LINGER, &reset, socklen_t(MemoryLayout<linger>.size))
        close(descriptor)
        hold.signal()

        let next = try client.exchange(DeviceSessionRequest(action: .read), timeout: 10)
        _ = try client.exchange(DeviceSessionRequest(action: .end), timeout: 5)

        #expect(next.n == 2)
        #expect(served.exit(within: 5)?.reason == .ended)
        withExtendedLifetime(container) {}
    }

    /// A host that connects and sends nothing is closed once the read timeout passes, and the next host is served.
    @Test
    func asilentConnectionIsClosedAfterTheReadTimeoutAndTheNextIsServed() throws {
        let session = try Self.readySession(readTimeout: 0.3)
        let (container, client, served) = (session.container, session.client, session.served)
        let descriptor = try DeviceSessionSocket.connect(address: "::1", port: client.port, timeout: 5)
        defer { close(descriptor) }
        let started = ContinuousClock.now

        let silent = DeviceSessionSocket.readLine(descriptor, cap: 16, timeout: 5)
        let waited = ContinuousClock.now - started
        let next = try client.exchange(DeviceSessionRequest(action: .read), timeout: 5)
        _ = try client.exchange(DeviceSessionRequest(action: .end), timeout: 5)

        #expect(silent == .closed(Data()))
        #expect(waited >= .milliseconds(250) && waited < .seconds(4))
        #expect(next.n == 1)
        #expect(served.exit(within: 5)?.reason == .ended)
        withExtendedLifetime(container) {}
    }

    /// A frame past the 1 MiB cap is closed unanswered, the host sees a closed connection rather than dying of SIGPIPE on its own write, and the next request is still 1.
    @Test
    func aframeOverTheCapIsClosed() throws {
        let session = try Self.readySession()
        let (container, client, served) = (session.container, session.client, session.served)
        let oversized = DeviceSessionRequest(action: .step, step: .tap(label: String(repeating: "a", count: 4 << 20)))

        #expect(throws: DeviceSessionClientError.closedWithoutAnswer) { try client.exchange(oversized, timeout: 5) }
        let next = try client.exchange(DeviceSessionRequest(action: .read), timeout: 5)
        _ = try client.exchange(DeviceSessionRequest(action: .end), timeout: 5)

        #expect(next.n == 1)
        #expect(served.exit(within: 5)?.served == 2)
        withExtendedLifetime(container) {}
    }

    /// An address the device does not hold is `EADDRNOTAVAIL`, which sends the runner back to waiting: the next `bind.json`, naming an address it does hold, binds.
    @Test
    func anaddressTheDeviceDoesNotHoldWaitsForTheNextBind() throws {
        try Self.onFreePort { port in
            let container = try TemporaryDirectory()
            let bindPath = LiveSessionLayout(directory: container.url).bind.path

            #expect(throws: DeviceSessionError.bindFailed(address: Self.gone, port: port, errno: EADDRNOTAVAIL)) {
                try DeviceSessionSocket.listen(address: Self.gone, port: port)
            }
            try Self.writeBind(DeviceSessionBind(session: Self.session, address: Self.gone, port: port, token: Self.token), in: container.url)
            let served = ServedSession.start(container: container.url)
            try Self.awaitRemoval(of: bindPath)
            try Self.writeBind(Self.bind(port: port), in: container.url)
            let ready = try Self.awaitReady(Self.client(port: port), served: served)
            _ = try Self.client(port: port).exchange(DeviceSessionRequest(action: .end), timeout: 5)

            #expect(ready == Self.ready)
            #expect(served.exit(within: 5)?.reason == .ended)
        }
    }

    /// A `bind.json` naming another session is deleted and not bound by; the runner waits on for its own.
    @Test
    func abindForAnotherSessionIsDeletedAndIgnored() throws {
        try Self.onFreePort { port in
            let container = try TemporaryDirectory()
            let bindPath = LiveSessionLayout(directory: container.url).bind.path
            try Self.writeBind(DeviceSessionBind(session: "another", address: "::1", port: port, token: Self.token), in: container.url)
            let served = ServedSession.start(container: container.url)

            try Self.awaitRemoval(of: bindPath)
            Thread.sleep(forTimeInterval: 0.2)
            #expect(throws: DeviceSessionClientError.refused) { try Self.client(port: port).hello() }
            try Self.writeBind(Self.bind(port: port), in: container.url)
            _ = try Self.awaitReady(Self.client(port: port), served: served)
            _ = try Self.client(port: port).exchange(DeviceSessionRequest(action: .end), timeout: 5)

            #expect(served.exit(within: 5)?.reason == .ended)
        }
    }

    /// No `bind.json` within the wait fails the session in words naming the file, and the exit record is still written.
    @Test
    func nobindWithinTheWaitFailsTheSessionSayingSo() throws {
        let container = try TemporaryDirectory()

        let exit = try #require(ServedSession.start(container: container.url, bindTimeout: 0.3).exit(within: 5))

        #expect(exit.reason == .failed)
        #expect(exit.detail.contains("no bind.json for session \(Self.session)"))
        #expect(try Self.sameRecord(Self.writtenExit(in: container.url), exit))
    }

    /// With no request for the whole timeout the session stops on its own and records why, over the socket as over files.
    @Test
    func asessionWithNoRequestGoesIdle() throws {
        let session = try Self.readySession(idle: 0.3)
        let (container, _, served) = (session.container, session.client, session.served)

        let exit = try #require(served.exit(within: 5))

        #expect(exit.reason == .idle)
        #expect(try Self.sameRecord(Self.writtenExit(in: container.url), exit))
    }

    /// Bound to the address `bind.json` names, the listener refuses every other address the Mac holds: the wildcard, which the LAN could reach, is never bound.
    @Test
    func thelistenerAnswersOnlyTheAddressItWasGiven() throws {
        let (listener, port) = try Self.onFreePort { port in
            do {
                return try (DeviceSessionSocket.listen(address: "::1", port: port), port)
            } catch DeviceSessionError.bindFailed(_, _, EADDRINUSE) {
                throw PortTaken()
            }
        }
        defer { close(listener) }
        let others = Self.nonLoopbackAddresses()
        try #require(!others.isEmpty, "this Mac has no non-loopback address to try the listener from, so the check cannot be made here")

        let loopback = try DeviceSessionSocket.connect(address: "::1", port: port, timeout: 5)
        close(loopback)
        let reached = others.filter { address in
            guard let descriptor = try? DeviceSessionSocket.connect(address: address, port: port, timeout: 2) else { return false }
            close(descriptor)
            return true
        }

        #expect(reached == [], "the listener bound to ::1 was reached through \(reached)")
    }

    /// A `bind.json` the host copies in while the runner holds its claim on the last one is bound by the next look: the claim was renamed aside, so the delete takes the claim and never the newer file.
    @Test
    func anewerBindLandingWhileTheLastIsClaimedSurvivesForTheNextLook() throws {
        try Self.onFreePort { port in
            let container = try TemporaryDirectory()
            try Self.writeBind(DeviceSessionBind(session: Self.session, address: Self.gone, port: port, token: Self.token), in: container.url)
            let directory = container.url
            let landed = OSAllocatedUnfairLock(initialState: false)
            let served = ServedSession.start(container: directory, bindTimeout: 3, afterClaim: {
                guard !landed.withLock({ $0 }) else { return }
                landed.withLock { $0 = true }
                try? Self.writeBind(Self.bind(port: port), in: directory)
            })
            let client = Self.client(port: port)

            let ready = try Self.awaitReady(client, served: served)
            _ = try client.exchange(DeviceSessionRequest(action: .end), timeout: 5)

            #expect(ready == Self.ready)
            #expect(served.exit(within: 5)?.reason == .ended)
        }
    }

    /// A `bind.json` that never decodes is waited past — the host's copy may still be landing — but deleted once the wait runs out, since it may carry a token; nothing of it, claim included, is left in the container.
    @Test
    func abindThatNeverDecodesIsDeletedWhenTheWaitRunsOut() throws {
        let container = try TemporaryDirectory()
        let layout = LiveSessionLayout(directory: container.url)
        try Data("{\"token\": \"\(Self.token.hex)\"".utf8).write(to: layout.bind)

        let exit = try #require(ServedSession.start(container: container.url, bindTimeout: 0.5).exit(within: 5))

        #expect(exit.reason == .failed)
        #expect(exit.detail.contains("is not a bind record"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: container.url.path) == [layout.exit.lastPathComponent])
    }

    /// A `bind.json` present when the runner binds — one that landed while it held its claim — is deleted as the wait ends, and one copied in afterwards is deleted when the session exits.
    @Test
    func abindLeftOnceTheRunnerHasBoundIsDeletedThenAndAtExit() throws {
        try Self.onFreePort { port in
            let container = try TemporaryDirectory()
            let bindPath = LiveSessionLayout(directory: container.url).bind.path
            try Self.writeBind(Self.bind(port: port), in: container.url)
            let served = ServedSession.start(container: container.url, afterClaim: {
                FileManager.default.createFile(atPath: bindPath, contents: Data("{\"token\":".utf8))
            })
            let client = Self.client(port: port)

            _ = try Self.awaitReady(client, served: served)
            let leftAtBind = FileManager.default.fileExists(atPath: bindPath)
            try Data("{\"token\":".utf8).write(to: URL(fileURLWithPath: bindPath))
            _ = try client.exchange(DeviceSessionRequest(action: .end), timeout: 5)
            let exit = served.exit(within: 5)

            #expect(!leftAtBind)
            #expect(exit?.reason == .ended)
            #expect(!FileManager.default.fileExists(atPath: bindPath))
        }
    }

    /// A host that sends its frame a byte every 0.2 s is closed once the 0.3 s read timeout has passed since it connected: the deadline is for the whole frame, never restarted by a byte arriving.
    @Test
    func atricklingConnectionIsClosedAtTheReadTimeoutForTheWholeFrame() throws {
        let session = try Self.readySession(readTimeout: 0.3)
        let (container, client, served) = (session.container, session.client, session.served)
        let descriptor = try DeviceSessionSocket.connect(address: "::1", port: client.port, timeout: 5)
        defer { close(descriptor) }
        let started = ContinuousClock.now

        var outcome = DeviceSessionSocket.LineRead.timedOut
        while outcome == .timedOut, ContinuousClock.now - started < .seconds(3) {
            _ = DeviceSessionSocket.send(descriptor, Data("{".utf8), timeout: 1)
            outcome = DeviceSessionSocket.readLine(descriptor, cap: 16, timeout: 0.2)
        }
        let waited = ContinuousClock.now - started
        let next = try client.exchange(DeviceSessionRequest(action: .read), timeout: 5)
        _ = try client.exchange(DeviceSessionRequest(action: .end), timeout: 5)

        #expect(outcome != .timedOut, "the trickling connection was still open after \(waited)")
        #expect(waited < .seconds(2))
        #expect(next.n == 1)
        #expect(served.exit(within: 5)?.reason == .ended)
        withExtendedLifetime(container) {}
    }

    /// A peer that reads a few bytes at a time cannot hold a write past its deadline: the deadline is for the whole write, never restarted by each part of it that goes.
    @Test
    func awriteToAPeerReadingSlowlyStopsAtItsOverallDeadline() throws {
        var pair: [Int32] = [0, 0]
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0)
        let (writer, reader) = (pair[0], pair[1])
        try #require(DeviceSessionSocket.prepare(writer))
        var small: Int32 = 8192
        setsockopt(writer, SOL_SOCKET, SO_SNDBUF, &small, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(reader, SOL_SOCKET, SO_RCVBUF, &small, socklen_t(MemoryLayout<Int32>.size))
        let readerDone = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            var buffer = [UInt8](repeating: 0, count: 512)
            let until = ContinuousClock.now + .seconds(4)
            while ContinuousClock.now < until, recv(reader, &buffer, buffer.count, 0) > 0 {
                Thread.sleep(forTimeInterval: 0.05)
            }
            close(reader)
            readerDone.signal()
        }
        let started = ContinuousClock.now

        let outcome = DeviceSessionSocket.send(writer, Data(count: 1 << 20), timeout: 0.5)
        let took = ContinuousClock.now - started
        close(writer)
        readerDone.wait()

        #expect(outcome == ETIMEDOUT)
        #expect(took >= .milliseconds(450) && took < .seconds(2), "the write took \(took)")
    }

    /// A reply past the 16 MiB a host reads is not sent: the host gets a failure under the same number, which it files, rather than a closed connection that would leave a gap; the next request is served under the next number.
    @Test
    func areplyOverTheCapIsAnsweredAsAFailureUnderItsNumber() throws {
        let session = try Self.readySession { request in
            guard request.n == 1 else { return LiveSessionResponse(n: request.n, action: request.action) }
            return LiveSessionResponse(n: request.n, action: request.action, failure: String(repeating: "x", count: DeviceSessionFrame.replyCap))
        }
        let (container, client, served) = (session.container, session.client, session.served)

        let reply = try client.exchange(DeviceSessionRequest(action: .read), timeout: 10)
        let next = try client.exchange(DeviceSessionRequest(action: .read), timeout: 5)
        _ = try client.exchange(DeviceSessionRequest(action: .end), timeout: 5)

        #expect(reply.n == 1)
        #expect(reply.action == .read)
        #expect(reply.failure?.contains("past the 16 MiB a host reads, so this failure was sent in its place") == true)
        #expect(next.n == 2)
        #expect(served.exit(within: 5)?.reason == .ended)
        withExtendedLifetime(container) {}
    }

    /// A reply has the read timeout plus a second per MiB to be written, whole, and never more than 30 s.
    @Test
    func areplysDeadlineGrowsWithItsSizeUpToThirtySeconds() {
        #expect(DeviceSessionTransport.replyTimeout(bytes: 0, readTimeout: 5) == 5)
        #expect(DeviceSessionTransport.replyTimeout(bytes: 16 << 20, readTimeout: 5) == 21)
        #expect(DeviceSessionTransport.replyTimeout(bytes: 64 << 20, readTimeout: 5) == 30)
    }

    fileprivate static var session: String {
        "session-1"
    }

    fileprivate static let ready = LiveSessionReady(
        device: CaptureManifest.Device(name: "iPad17,1", udid: "00008150-000A", osVersion: "27.0.1"),
        runnerCommit: "c0ffee",
        readyAt: Date(timeIntervalSince1970: 1_000_000)
    )

    fileprivate static let token = DeviceSessionToken(bytes: Array(repeating: 0x5A, count: DeviceSessionToken.byteCount))

    /// An address this Mac does not hold, which a bind meets with `EADDRNOTAVAIL`.
    private static var gone: String {
        "fd00:dead:beef::1"
    }

    /// How many ports ``onFreePort(_:)`` tries before letting a taken one fail the test.
    private static let portAttempts = 5

    /// The `exit.json` the transport wrote into the container.
    private static func writtenExit(in container: URL) throws -> LiveSessionExit? {
        try LiveSessionChannel(layout: LiveSessionLayout(directory: container)).exitRecord()
    }

    /// Whether `written` is `exit` as the file keeps it: a timestamp is written to the millisecond, so a stop read from the real clock comes back within one.
    private static func sameRecord(_ written: LiveSessionExit?, _ exit: LiveSessionExit) -> Bool {
        guard let written else { return false }
        return written.reason == exit.reason && written.detail == exit.detail && written.served == exit.served
            && abs(written.stoppedAt.timeIntervalSince(exit.stoppedAt)) < 0.001
    }

    private static func bind(port: UInt16) -> DeviceSessionBind {
        DeviceSessionBind(session: session, address: "::1", port: port, token: token)
    }

    private static func client(port: UInt16) -> DeviceSessionClient {
        DeviceSessionClient(address: "::1", port: port, token: token)
    }

    /// A session bound on loopback and answering hellos, with its container, a client and the served loop.
    private static func readySession(
        readTimeout: TimeInterval = 5,
        idle: TimeInterval = 30,
        answer: @escaping @Sendable (LiveSessionRequest) -> LiveSessionResponse = { LiveSessionResponse(n: $0.n, action: $0.action) }
    ) throws -> ReadySession {
        try onFreePort { port in
            let container = try TemporaryDirectory()
            try writeBind(bind(port: port), in: container.url)
            let served = ServedSession.start(container: container.url, readTimeout: readTimeout, idle: idle, answer: answer)
            let client = client(port: port)
            _ = try awaitReady(client, served: served)
            return ReadySession(container: container, client: client, served: served)
        }
    }

    /// `body` run on a port ``freePort()`` found free, and again on a fresh one each time it throws ``PortTaken``: the probe releases its port before the runner binds it, so another process can take it between the two.
    private static func onFreePort<Value>(_ body: (UInt16) throws -> Value) throws -> Value {
        for _ in 1 ..< portAttempts {
            do {
                return try body(freePort())
            } catch is PortTaken {
                continue
            }
        }
        return try body(freePort())
    }

    private static func writeBind(_ bind: DeviceSessionBind, in directory: URL) throws {
        try CaptureBundle.encoder().encode(bind).write(to: LiveSessionLayout(directory: directory).bind, options: .atomic)
    }

    /// Says hello until the runner answers, as `session start` does; throws ``PortTaken`` when the runner stopped because another process holds its port, and the runner's own exit when it stopped otherwise.
    private static func awaitReady(_ client: DeviceSessionClient, served: ServedSession) throws -> LiveSessionReady {
        let deadline = ContinuousClock.now + .seconds(10)
        while true {
            do {
                return try client.hello()
            } catch DeviceSessionClientError.refused where ContinuousClock.now < deadline {
                if let exit = served.exit(within: 0) {
                    guard exit.detail != "\(DeviceSessionError.bindFailed(address: client.address, port: client.port, errno: EADDRINUSE))" else { throw PortTaken() }
                    throw Timeout(description: "the runner stopped before it was ready: \(exit.detail)")
                }
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }

    private static func awaitRemoval(of path: String) throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while FileManager.default.fileExists(atPath: path) {
            guard ContinuousClock.now < deadline else { throw Timeout(description: "\(path) was never taken") }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    /// A loopback port nothing listens on: bound to port 0 for the kernel to choose, read back, and released.
    private static func freePort() throws -> UInt16 {
        let probe = try DeviceSessionSocket.listen(address: "::1", port: 0)
        defer { close(probe) }
        var address = sockaddr_in6()
        var length = socklen_t(MemoryLayout<sockaddr_in6>.size)
        let read = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(probe, $0, &length) }
        }
        guard read == 0 else { throw Timeout(description: "getsockname failed: errno \(errno)") }
        return UInt16(bigEndian: address.sin6_port)
    }

    /// Every IPv4 and routable IPv6 address on this Mac's interfaces other than loopback; link-local IPv6 is left out, as it needs a scope to connect to.
    private static func nonLoopbackAddresses() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        var found: [String] = []
        var cursor = head
        while let entry = cursor?.pointee {
            cursor = entry.ifa_next
            guard let socketAddress = entry.ifa_addr, entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let family = Int32(socketAddress.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6,
                  getnameinfo(socketAddress, socklen_t(socketAddress.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let address = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if family == AF_INET6, address.lowercased().hasPrefix("fe80") || address.contains("%") {
                continue
            }
            found.append(address)
        }
        return found
    }
}

extension DeviceSessionTransportTests {
    /// A device runner's loop served on a thread of its own, as the runner serves it, whose exit record the test waits for.
    final class ServedSession: @unchecked Sendable {
        private let lock = NSLock()
        private let finished = DispatchSemaphore(value: 0)
        private var record: LiveSessionExit?

        static func start(
            container: URL,
            readTimeout: TimeInterval = 5,
            bindTimeout: TimeInterval = 10,
            idle: TimeInterval = 30,
            answer: @escaping @Sendable (LiveSessionRequest) -> LiveSessionResponse = { LiveSessionResponse(n: $0.n, action: $0.action) },
            afterClaim: @escaping @Sendable () -> Void = {}
        ) -> ServedSession {
            let served = ServedSession()
            Thread.detachNewThread {
                let transport = DeviceSessionTransport(
                    launch: LiveSessionLaunch(appBundleID: "app.example", state: nil),
                    session: DeviceSessionTransportTests.session,
                    container: container,
                    readTimeout: readTimeout,
                    bindTimeout: bindTimeout
                )
                transport.afterClaim = afterClaim
                let exit = DeviceSessionLoop(transport: transport, idle: LiveSessionIdle(timeout: idle)).run(
                    heartbeat: .onDevice,
                    start: { _ in DeviceSessionTransportTests.ready },
                    answer: answer,
                    handBack: {},
                    now: { Date() },
                    pause: { Thread.sleep(forTimeInterval: $0) }
                )
                served.finish(exit)
            }
            return served
        }

        /// The exit record, once the loop has returned within `timeout`; `nil` if it has not.
        func exit(within timeout: TimeInterval) -> LiveSessionExit? {
            guard finished.wait(timeout: .now() + timeout) == .success else { return nil }
            finished.signal()
            return lock.withLock { record }
        }

        private func finish(_ exit: LiveSessionExit) {
            lock.withLock { record = exit }
            finished.signal()
        }
    }

    /// A session bound and answering, with the container it writes into and a client of it.
    struct ReadySession {
        let container: TemporaryDirectory
        let client: DeviceSessionClient
        let served: ServedSession
    }

    /// A wait in a test's own scaffolding that ran out.
    struct Timeout: Error, CustomStringConvertible {
        let description: String
    }

    /// The port a test was given was taken by another process before the runner bound it; ``onFreePort(_:)`` tries a fresh one.
    struct PortTaken: Error {}
}
