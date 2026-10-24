//
// Copyright © Agulhas Labs
//

import Foundation

/// The file channel between a live session's host and its resident runner: numbered requests in, numbered responses out.
///
/// **Every file is written whole or not at all**: into a temporary name in the same directory, then renamed, so a reader polling for `<n>.json` sees either nothing or the complete file — never a torn one. A request is renamed *exclusively* (`RENAME_EXCL`), which is what numbers requests: two hosts sending at once cannot both claim `n`, and the loser takes `n + 1`.
///
/// Both sides use this one type — the host to ``send(_:)`` and ``awaitResponse(to:timeout:isRunnerAlive:pause:now:)``, the runner to ``request(_:)`` and ``respond(_:)`` — so neither can read a file the other did not write in this shape.
public struct LiveSessionChannel: Sendable {
    public let layout: LiveSessionLayout

    public init(layout: LiveSessionLayout) {
        self.layout = layout
    }

    /// Creates the directory and its request and response directories.
    public func prepare() throws {
        for url in [layout.requests, layout.responses] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// Sends `action` as the next request — with the route step a `step` takes, the hash it is guarded by the drag a `scroll` makes and whether a `read` also takes a screenshot — and returns its number.
    public func send(_ action: LiveSessionRequest.Action, step: Walkbook.RouteStep? = nil, guardHash: String? = nil, scroll: LiveSessionScroll? = nil, screenshot: Bool = false) throws -> Int {
        var number = (layout.requestNumbers().last ?? 0) + 1
        while true {
            let request = LiveSessionRequest(n: number, action: action, step: step, guardHash: guardHash, scroll: scroll, screenshot: screenshot)
            let data = try Self.encode(request, path: layout.request(number).path)
            if try Self.write(data, to: layout.request(number), exclusively: true) {
                return number
            }
            number += 1
        }
    }

    /// Files a device's exchange — `request` and the `response` the runner gave it — under the number the runner gave it, so ``route()``, ``landedSteps(since:)`` and `save` read a device's session as they read a simulator's.
    ///
    /// The request is filed exclusively and first: one already there would mean two answers under one number, and is refused rather than overwritten (Brief, "Live sessions on a physical device", ruling 4).
    public func file(_ request: DeviceSessionRequest, answeredBy response: LiveSessionResponse) throws {
        let url = layout.request(response.n)
        guard response.n > 0 else {
            throw LiveSessionError.malformed(path: url.path, reason: "the runner numbered its response \(response.n); requests are numbered from 1")
        }
        guard try Self.write(Self.encode(request.numbered(response.n), path: url.path), to: url, exclusively: true) else {
            throw LiveSessionError.alreadyFiled(number: response.n, path: url.path)
        }
        try respond(response)
    }

    /// Request `number`, once it has been sent; `nil` until then.
    public func request(_ number: Int) throws -> LiveSessionRequest? {
        guard let request = try Self.read(LiveSessionRequest.self, at: layout.request(number)) else { return nil }
        guard request.n == number else {
            throw LiveSessionError.malformed(path: layout.request(number).path, reason: "it states request \(request.n)")
        }
        return request
    }

    /// Files `response` under the number of the request it answers.
    public func respond(_ response: LiveSessionResponse) throws {
        let url = layout.response(response.n)
        _ = try Self.write(Self.encode(response, path: url.path), to: url, exclusively: false)
    }

    /// The response to request `number`, once the runner has filed it; `nil` until then.
    ///
    /// Asking after a request that was never sent is refused, rather than waited on for ever.
    public func response(to number: Int) throws -> LiveSessionResponse? {
        guard FileManager.default.fileExists(atPath: layout.request(number).path) else {
            throw LiveSessionError.noSuchRequest(number: number, path: layout.request(number).path)
        }
        guard let response = try Self.read(LiveSessionResponse.self, at: layout.response(number)) else { return nil }
        guard response.n == number else {
            throw LiveSessionError.malformed(path: layout.response(number).path, reason: "it answers request \(response.n)")
        }
        return response
    }

    /// The steps that landed since launch, in the order the runner took them, each as a walk records it — the route a saved walkbook replays.
    ///
    /// **Read from the responses, not kept beside them.** The runner serves requests strictly in number order and files each step's answer under its number, so the answered `step`s, landed ones only, in number order *are* the route; a second list kept alongside would be a second statement of it, free to disagree. A step still unanswered is not in it yet.
    public func route() throws -> [Walkbook.RouteStep] {
        try landedSteps().map(\.step)
    }

    /// ``route()`` with the request each step answered, from request `first` on — what `session save --since` slices.
    ///
    /// **A `relaunch` starts the route over**: it puts the app back at launch, so only steps after the last answered `relaunch` belong to it.
    public func landedSteps(since first: Int = 1) throws -> [LandedStep] {
        let numbers = layout.requestNumbers()
        let afterRelaunch = try numbers.last { try Self.read(LiveSessionResponse.self, at: layout.response($0))?.action == .relaunch }.map { $0 + 1 } ?? 1
        return try numbers.filter { $0 >= max(first, afterRelaunch) }.compactMap { number in
            try Self.read(LiveSessionResponse.self, at: layout.response(number))?.step?.landed.map { LandedStep(request: number, step: $0) }
        }
    }

    /// The numbers from request `first` up to the last one filed under which no request is filed, ascending; empty when the range has no gap.
    ///
    /// **Only a device's session can have one** (Brief, "Live sessions on a physical device", ruling 4): its runner numbers each request as it serves it, and the host files the exchange afterwards, so a host killed between the answer and the filing, or that never read the answer, leaves a number the runner served and this Mac never filed. A simulator's host claims each number by filing the request before the runner sees it, so its numbers cannot skip.
    public func unfiledRequests(since first: Int = 1) -> [Int] {
        let filed = layout.requestNumbers()
        guard let last = filed.last, last >= first else { return [] }
        return Array(Set(max(first, 1) ... last).subtracting(filed)).sorted()
    }

    /// The `step` requests from request `first` on that were answered without landing — blocked, or failed — which a saved route leaves out though each may have acted on the app.
    ///
    /// A step refused on its guard is not among them: it was not taken, so it changed nothing a replay would miss.
    public func unlandedSteps(since first: Int = 1) throws -> [LiveSessionRequest] {
        try layout.requestNumbers().filter { $0 >= first }.compactMap { number in
            guard let response = try Self.read(LiveSessionResponse.self, at: layout.response(number)), response.action == .step,
                  response.step?.outcome != .landed, response.step?.outcome != .snapshotChanged else { return nil }
            return try request(number)
        }
    }

    /// Polls for the response to request `number` until it arrives, the runner stops, or `timeout` passes.
    ///
    /// A runner that wrote its exit record, or is no longer alive, has stopped — whatever it said on the way out is the refusal.
    public func awaitResponse(
        to number: Int,
        timeout: TimeInterval,
        isRunnerAlive: () -> Bool,
        pause: (TimeInterval) -> Void,
        now: () -> Date
    ) throws -> LiveSessionResponse {
        let started = now()
        while true {
            if let response = try response(to: number) {
                return response
            }
            let exit = try exitRecord()
            if exit != nil || !isRunnerAlive() {
                // The response may have landed between the two reads; the runner writes it before its exit record.
                if let response = try response(to: number) {
                    return response
                }
                throw LiveSessionError.runnerExited(number: number, exit: exit)
            }
            guard now().timeIntervalSince(started) < timeout else {
                throw LiveSessionError.noResponse(number: number, waited: timeout)
            }
            pause(Self.pollInterval)
        }
    }

    /// Writes what the runner launches.
    public func writeLaunch(_ launch: LiveSessionLaunch) throws {
        _ = try Self.write(Self.encode(launch, path: layout.launch.path), to: layout.launch, exclusively: false)
    }

    /// What the runner launches; `nil` when the host wrote nothing.
    public func launch() throws -> LiveSessionLaunch? {
        try Self.read(LiveSessionLaunch.self, at: layout.launch)
    }

    /// Marks the runner ready.
    public func markReady(_ ready: LiveSessionReady) throws {
        _ = try Self.write(Self.encode(ready, path: layout.ready.path), to: layout.ready, exclusively: false)
    }

    /// The runner's ready record; `nil` until it has written one.
    public func readyRecord() throws -> LiveSessionReady? {
        try Self.read(LiveSessionReady.self, at: layout.ready)
    }

    /// Records why the runner stopped.
    public func markExit(_ exit: LiveSessionExit) throws {
        _ = try Self.write(Self.encode(exit, path: layout.exit.path), to: layout.exit, exclusively: false)
    }

    /// Why the runner stopped; `nil` while it is serving, or when it stopped without saying.
    public func exitRecord() throws -> LiveSessionExit? {
        try Self.read(LiveSessionExit.self, at: layout.exit)
    }

    /// Writes one beat of the runner's heartbeat.
    public func markHeartbeat(_ heartbeat: LiveSessionHeartbeat) throws {
        _ = try Self.write(Self.encode(heartbeat, path: layout.heartbeat.path), to: layout.heartbeat, exclusively: false)
    }

    /// The runner's last beat; `nil` when there is none — a runner from before the heartbeat, one that never reached serving, or one whose last beat could not be written and was removed.
    public func heartbeat() throws -> LiveSessionHeartbeat? {
        try Self.read(LiveSessionHeartbeat.self, at: layout.heartbeat)
    }

    /// The latest a runner that is no longer running can have stopped, as far as its files say: ``exitRecord()``'s stop time, else its ``heartbeat()``'s ``LiveSessionHeartbeat/latestStop``, else `nil` — a runner that left neither.
    ///
    /// **One reading for every host-side handback** — `session list`'s and `session end`'s — so the two never place the same stop differently: a stop placed too early takes a teardown still to come as long past (SimWalk#76). A file that cannot be read is no bound, the same as one that is absent.
    public func latestStop() -> Date? {
        (try? exitRecord())?.stoppedAt ?? (try? heartbeat())?.latestStop
    }

    /// How long either side waits between polls — noise beside a UI settle.
    public static var pollInterval: TimeInterval {
        0.05
    }

    /// Writes `data` to `url` whole: into a temporary file beside it, then renamed over it — or, `exclusively`, renamed only if nothing is there yet, answering whether it was.
    static func write(_ data: Data, to url: URL, exclusively: Bool) throws -> Bool {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary)
        } catch {
            throw LiveSessionError.notWritable(path: url.path, reason: error.localizedDescription)
        }
        let renamed = renamex_np(temporary.path, url.path, exclusively ? UInt32(RENAME_EXCL) : 0) == 0
        let failure = errno
        guard renamed else {
            try? FileManager.default.removeItem(at: temporary)
            if exclusively, failure == EEXIST {
                return false
            }
            throw LiveSessionError.notWritable(path: url.path, reason: String(cString: strerror(failure)))
        }
        return true
    }

    private static func encode(_ value: some Encodable, path: String) throws -> Data {
        do {
            return try CaptureBundle.encoder().encode(value)
        } catch {
            throw LiveSessionError.notWritable(path: path, reason: "\(error)")
        }
    }

    private static func read<Value: Decodable>(_ type: Value.Type, at url: URL) throws -> Value? {
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        do {
            return try CaptureBundle.decoder().decode(type, from: data)
        } catch {
            throw LiveSessionError.malformed(path: url.path, reason: "\(error)")
        }
    }
}

extension LiveSessionChannel: LiveSessionTransport {
    /// A simulator's runner beats a heartbeat into the session directory, so the loop takes one that was started.
    public typealias Liveness = LiveSessionHeartbeat.Running

    /// ``launch()``, or the failure of a session the host gave nothing to launch.
    public func launchRecord() throws -> LiveSessionLaunch {
        guard let launch = try launch() else {
            throw NoLaunch(description: "no launch record at \(layout.launch.path): the host writes it before starting the runner")
        }
        return launch
    }

    /// A poll of the directory returns at once, so the loop pauses ``pollInterval`` before the next.
    public func afterEmptyPoll(pause: (TimeInterval) -> Void) {
        pause(Self.pollInterval)
    }
}

extension LiveSessionChannel {
    /// Why a runner could not serve at all: the host wrote no `launch.json`.
    struct NoLaunch: Error, CustomStringConvertible {
        let description: String
    }
}

public extension LiveSessionChannel {
    /// A step that landed, and the number of the request that took it.
    struct LandedStep: Equatable, Sendable {
        public let request: Int
        public let step: Walkbook.RouteStep

        public init(request: Int, step: Walkbook.RouteStep) {
            self.request = request
            self.step = step
        }
    }
}
