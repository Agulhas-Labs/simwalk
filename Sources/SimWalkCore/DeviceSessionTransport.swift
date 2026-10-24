//
// Copyright © Agulhas Labs
//

import Foundation

/// The runner's side of a live session on a physical device: a TCP listener on the tunnel address, serving one exchange per connection to a host that presents the session's token.
///
/// **It binds where `bind.json` says and nowhere else.** ``markReady(_:)`` waits for a `bind.json` naming this session in the container directory, claims it by renaming it aside, deletes the claim once read, and binds the address and port it names; an address the device no longer holds (`EADDRNOTAVAIL`, a tunnel that dropped as the host read it) goes back to waiting for the host's next one. Never the wildcard: `[::]` answered the LAN (Brief, "Live sessions on a physical device", ruling 1).
///
/// **No `bind.json` outlives the wait**: each carries the session's token, so whatever is left in the container — one that never decoded, one that arrived after the bind — is deleted when the wait ends, bound or not, and again by ``markExit(_:)``.
///
/// **A frame is believed only once its token matches**, compared in constant time. A connection whose frame is not JSON, carries a wrong or missing token, runs past ``DeviceSessionFrame/requestCap`` or has not arrived within the read timeout is closed without a byte of answer and takes no number. A `hello` is answered with the ready record and takes no number either; a request is served as `served + 1` and answered on its own connection, which is then closed (rulings 2–4).
///
/// **One connection at a time**: a second host waits in the backlog while the first is served. ``request(_:)`` waits for a connection in `poll(2)` for up to ``LiveSessionChannel/pollInterval`` and takes it the moment it arrives, so the loop does not pause again after it (``afterEmptyPoll(pause:)``).
///
/// `exit.json` is written into the container directory in the session files' own encoding, where the host copies it back from once the runner is gone (ruling 6).
public final class DeviceSessionTransport: LiveSessionTransport {
    /// A device has no heartbeat, so the loop takes the form that says so.
    public typealias Liveness = NoHeartbeat

    private let launch: LiveSessionLaunch
    private let session: String
    private let container: LiveSessionLayout
    private let readTimeout: TimeInterval
    private let bindTimeout: TimeInterval
    private let now: () -> Date
    private let pause: (TimeInterval) -> Void
    /// The token `bind.json` carried; `nil` until bound.
    private var token: DeviceSessionToken?
    private var listener: Int32?
    /// The connection whose request is being served, answered by ``respond(_:)``.
    private var connection: Int32?
    /// The ready record as a frame, answered to every `hello`.
    private var readyFrame = Data()
    /// Runs between claiming `bind.json` and reading the claim: the seam a test lands a newer `bind.json` through.
    var afterClaim: () -> Void = {}

    /// - Parameters:
    ///   - launch: what the runner launches, which the host passed in its environment.
    ///   - session: the session's id; a `bind.json` naming another is deleted and waited past.
    ///   - container: the runner's `Documents/SimWalkSession/`, where `bind.json` arrives and `exit.json` is written.
    ///   - readTimeout: how long an accepted connection has to deliver its frame — and an answer to make progress being written — before it is closed.
    ///   - bindTimeout: how long to wait for a `bind.json` that binds: the host's own ready timeout, past which nobody is waiting.
    ///   - now: the clock the bind wait is measured on.
    ///   - pause: waits between looks for `bind.json`.
    public init(
        launch: LiveSessionLaunch,
        session: String,
        container: URL,
        readTimeout: TimeInterval = 5,
        bindTimeout: TimeInterval = 180,
        now: @escaping () -> Date = { Date() },
        pause: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.launch = launch
        self.session = session
        self.container = LiveSessionLayout(directory: container)
        self.readTimeout = readTimeout
        self.bindTimeout = bindTimeout
        self.now = now
        self.pause = pause
    }

    deinit {
        connection.map { _ = Darwin.close($0) }
        listener.map { _ = Darwin.close($0) }
    }

    /// The launch the host passed, which a device's runner has from its environment rather than a file.
    public func launchRecord() throws -> LiveSessionLaunch {
        launch
    }

    /// Keeps `ready` to answer each `hello` with, then waits for this session's `bind.json` and listens where it says.
    public func markReady(_ ready: LiveSessionReady) throws {
        readyFrame = try DeviceSessionFrame.encode(DeviceSessionFrame.Outbound(ready: ready))
        try FileManager.default.createDirectory(at: container.directory, withIntermediateDirectories: true)
        let started = now()
        var lastProblem: String?
        defer { removeBinds() }
        while true {
            if let bind = takeBind(problem: &lastProblem) {
                do {
                    listener = try DeviceSessionSocket.listen(address: bind.address, port: bind.port)
                    token = bind.token
                    return
                } catch let DeviceSessionError.bindFailed(address, port, code) where code == EADDRNOTAVAIL {
                    lastProblem = "\(DeviceSessionError.bindFailed(address: address, port: port, errno: code))"
                }
            }
            guard now().timeIntervalSince(started) < bindTimeout else {
                throw DeviceSessionError.noBind(session: session, path: container.bind.path, waited: bindTimeout, lastProblem: lastProblem)
            }
            pause(LiveSessionChannel.pollInterval)
        }
    }

    /// The next authenticated request, numbered `number`, from a connection that arrives within the poll interval; `nil` when none did, or the one that did was refused or was a `hello`.
    ///
    /// An authenticated frame that is neither a `hello` nor a request this runner reads is thrown, its connection kept for the failure the loop answers under `number`.
    public func request(_ number: Int) throws -> LiveSessionRequest? {
        closeConnection()
        guard let listener, let token,
              DeviceSessionSocket.wait(listener, for: Int16(POLLIN), until: ContinuousClock.now + .seconds(LiveSessionChannel.pollInterval)),
              let accepted = DeviceSessionSocket.accept(listener) else { return nil }
        guard case let .line(line) = DeviceSessionSocket.readLine(accepted, cap: DeviceSessionFrame.requestCap, timeout: readTimeout),
              let presented = try? DeviceSessionFrame.decode(DeviceSessionFrame.Presented.self, from: line),
              token.matches(presented.token)
        else {
            Darwin.close(accepted)
            return nil
        }
        connection = accepted
        let frame: DeviceSessionFrame.Inbound
        do {
            frame = try DeviceSessionFrame.decode(DeviceSessionFrame.Inbound.self, from: line)
        } catch {
            throw DeviceSessionError.malformedFrame(reason: "\(error)")
        }
        switch (frame.hello ?? false, frame.request) {
        case (true, nil):
            _ = DeviceSessionSocket.send(accepted, readyFrame, timeout: readTimeout)
            closeConnection()
            return nil
        case let (false, request?):
            return request.numbered(number)
        default:
            throw DeviceSessionError.malformedFrame(reason: "a frame carries `hello` or a `request`, exactly one of them")
        }
    }

    /// ``request(_:)`` has already waited in `poll(2)`; a second wait would only delay the next host.
    public func afterEmptyPoll(pause _: (TimeInterval) -> Void) {}

    /// Writes `response` on the connection its request came in on, within ``replyTimeout(bytes:readTimeout:)`` for the whole reply, then closes it.
    ///
    /// **A host that has gone is not the session's failure**: the write fails with `EPIPE` rather than raising SIGPIPE, and is dropped; so is one the host reads too slowly to finish within the deadline. The request was served under its number, and the host that left without the answer leaves that number unfiled, which `save` refuses by name.
    ///
    /// **A reply past ``DeviceSessionFrame/replyCap`` is not sent** (``reply(_:)``): the host would close on it and leave a gap; it gets a failure under the same number instead, which it files.
    public func respond(_ response: LiveSessionResponse) throws {
        guard let connection else { return }
        defer { closeConnection() }
        let reply = try Self.reply(response)
        _ = DeviceSessionSocket.send(connection, reply, timeout: Self.replyTimeout(bytes: reply.count, readTimeout: readTimeout))
    }

    /// `response` as the frame a host reads; or, when that would run past ``DeviceSessionFrame/replyCap`` — which the host closes on, filing nothing — the same response without its screenshot and with ``LiveSessionResponse/screenshotRefusal`` saying why, or failing that a failure under the same number and action that says so, which the host files as it would any failure.
    static func reply(_ response: LiveSessionResponse) throws -> Data {
        let frame = try DeviceSessionFrame.encode(DeviceSessionFrame.Outbound(response: response))
        let length = frame.count - 1
        guard length > DeviceSessionFrame.replyCap else { return frame }
        if let screenshot = response.screenshot {
            let mebibytes = (screenshot.count + (1 << 20) - 1) >> 20
            let refusal = "the screenshot (\(mebibytes) MiB) would take the reply past the \(DeviceSessionFrame.replyCap >> 20) MiB a host reads"
            let without = LiveSessionResponse(n: response.n, action: response.action, screen: response.screen, step: response.step, failure: response.failure, screenshotRefusal: refusal)
            let trimmed = try DeviceSessionFrame.encode(DeviceSessionFrame.Outbound(response: without))
            if trimmed.count - 1 <= DeviceSessionFrame.replyCap {
                return trimmed
            }
        }
        let failure = "the runner served this request, but its reply ran to \(length) bytes, past the \(DeviceSessionFrame.replyCap >> 20) MiB a host reads, so this failure was sent in its place; what the request did to the app is not in it"
        return try DeviceSessionFrame.encode(DeviceSessionFrame.Outbound(response: LiveSessionResponse(n: response.n, action: response.action, failure: failure)))
    }

    /// How long a reply of `bytes` has, start to finish, to be written: the read timeout plus one second per MiB, never more than 30 s — 5 s for a small reply and 21 s for one at the 16 MiB cap, with the defaults.
    ///
    /// **One deadline for the whole reply**, so a host that reads a few bytes at a time cannot hold the runner, and with it every other host, for longer than this.
    static func replyTimeout(bytes: Int, readTimeout: TimeInterval) -> TimeInterval {
        min(readTimeout + Double(bytes) / Double(1 << 20), 30)
    }

    /// Stops listening, so a host's next connect is refused, deletes any `bind.json` left in the container, and writes `exit`, stamped with this session's id, to `exit.json` there: the container is the same path for every session, so the id is what tells the host this record is its own.
    public func markExit(_ exit: LiveSessionExit) throws {
        closeConnection()
        listener.map { _ = Darwin.close($0) }
        listener = nil
        removeBinds()
        try FileManager.default.createDirectory(at: container.directory, withIntermediateDirectories: true)
        try LiveSessionChannel(layout: container).markExit(exit.stamped(session: session))
    }

    /// This session's `bind.json`, claimed, read and deleted; `nil` when there is none yet.
    ///
    /// **Claimed before it is read**: renamed to ``claimedBind`` in the same directory, so the file read is the file deleted, and a newer `bind.json` the host copies in meanwhile lands beside the claim for the next look rather than being deleted unread. One naming another session is deleted and passed over. One that does not decode — the host's copy still landing — goes back under its own name for the next look, unless a newer one has arrived since, which supersedes it; noted as `problem`.
    private func takeBind(problem: inout String?) -> DeviceSessionBind? {
        guard Darwin.rename(container.bind.path, claimedBind.path) == 0 else { return nil }
        afterClaim()
        defer { try? FileManager.default.removeItem(at: claimedBind) }
        let bind: DeviceSessionBind
        do {
            bind = try CaptureBundle.decoder().decode(DeviceSessionBind.self, from: Data(contentsOf: claimedBind))
        } catch {
            problem = "\(container.bind.path) is not a bind record: \(error)"
            _ = renamex_np(claimedBind.path, container.bind.path, UInt32(RENAME_EXCL))
            return nil
        }
        guard bind.session == session else {
            problem = "a bind.json for session \(bind.session) was deleted"
            return nil
        }
        return bind
    }

    /// Where a `bind.json` is renamed to while it is read: beside it, so the rename is atomic, and under a name the host never writes.
    private var claimedBind: URL {
        container.directory.appendingPathComponent(".bind.claimed")
    }

    /// Deletes `bind.json` and any claim of one, each carrying a token no longer wanted.
    private func removeBinds() {
        try? FileManager.default.removeItem(at: container.bind)
        try? FileManager.default.removeItem(at: claimedBind)
    }

    private func closeConnection() {
        connection.map { _ = Darwin.close($0) }
        connection = nil
    }
}

public extension DeviceSessionTransport {
    /// A device runner's word that it has no heartbeat, which the loop takes where a simulator's runner hands it a beating one.
    ///
    /// **A device has none** (Brief, "Live sessions on a physical device", ruling 6): the heartbeat bounds a dead simulator runner's stop for the accessibility handback, which a device has no form of. Named rather than an optional, so a simulator runner cannot leave its heartbeat out by passing `nil`.
    enum NoHeartbeat: LiveSessionLiveness {
        case onDevice

        /// Nothing beats, so nothing stops.
        public func stop(_: LiveSessionExitRecorded) {}
    }
}
