//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkMCP
import SimWalkTestSupport
import Testing

/// A server over pipes whose waits are on a ``ManualClock`` and whose walk is a fake the test moves through gates (`Docs/Reference.md`, "Bounded walks").
///
/// **Every test ends, even one that fails.** ``run(_:directory:client:_:)`` tears the rig down whatever the body did: it opens every gate, releases the clock, closes the server's input and waits a bounded time for the server to exit; every wait for a response is bounded too (``Watched/limit``). A test that fails therefore fails in seconds, never holding the process open on a gated walk.
final class BoundedServerRig: @unchecked Sendable {
    static let budget = 10.0

    let clock = ManualClock()
    let directory: TemporaryDirectory
    let walk: FakeWalk
    /// The fake walk's gates and what it has done, and whether the server has exited.
    let events = Watched(Events())
    private let input = Pipe()
    private let output = Pipe()
    private let lines = Watched([String]())
    private let inputClosed = Watched(false)

    /// `client` is `SIMWALK_MCP_CLIENT`; `nil` leaves the mode to an `initialize` the test sends.
    private init(walk: FakeWalk, directory: TemporaryDirectory, client: String?) {
        self.walk = walk
        self.directory = directory
        let accumulator = FileHandleLines.Accumulator()
        output.fileHandleForReading.readabilityHandler = { [lines] handle in
            let read = accumulator.append(handle.availableData)
            lines.update { $0.append(contentsOf: read) }
        }
        var environment = [MCPCallBudget.environmentKey: String(Self.budget)]
        environment["SIMWALK_MCP_CLIENT"] = client
        let url = directory.url
        let server = SimWalkMCPServer(
            input: input.fileHandleForReading,
            output: output.fileHandleForWriting,
            log: { _ in },
            usage: UsageLog(directory: directory.url, now: { Date() }),
            session: nil,
            answering: { [walk, events] tool, _, _, started in
                guard tool == .walk else { return MCPExchange.answer }
                return walk.run(in: url, events: events, started: started)
            },
            environment: environment,
            clock: { [clock] in clock.now },
            sleep: { [clock] in await clock.sleep(for: $0) }
        )
        Task { [events] in
            await server.run()
            events.update { $0.serverExitedAfterWalk = $0.walkReturned }
            events.update { $0.serverExited = true }
        }
    }

    /// Runs `body` against a fresh server, then tears it down — after a failure too — and checks the server exited.
    static func run(
        _ walk: FakeWalk = FakeWalk(),
        directory: TemporaryDirectory? = nil,
        client: String? = "Cursor",
        sourceLocation: SourceLocation = #_sourceLocation,
        _ body: (BoundedServerRig) async throws -> Void
    ) async throws {
        let rig = try BoundedServerRig(walk: walk, directory: directory ?? TemporaryDirectory(), client: client)
        do {
            try await body(rig)
        } catch {
            await rig.tearDown(sourceLocation: sourceLocation)
            throw error
        }
        await rig.tearDown(sourceLocation: sourceLocation)
    }

    /// Writes one request line.
    func send(_ request: [String: Any]) throws {
        try send(line: JSONSerialization.data(withJSONObject: request))
    }

    /// Writes `line` as given, then a newline.
    func send(line: Data) throws {
        var line = line
        line.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: line)
    }

    /// A `walk_status` call.
    func poll(id: Int, _ handle: some StringProtocol) throws {
        try send(MCPExchange.call(id: id, tool: "walk_status", arguments: ["handle": String(handle)]))
    }

    /// A `walk` call.
    func callWalk(id: Int) throws {
        try send(MCPExchange.call(id: id, tool: "walk", arguments: ["walkbook": "book.json", "output": "out.simwalk"]))
    }

    /// The next response the server writes, waiting at most ``Watched/limit``.
    func next(sourceLocation: SourceLocation = #_sourceLocation) async throws -> [String: Any] {
        let line = try await lines.wait("a response from the server") { $0.isEmpty ? nil : $0.removeFirst() }
        return try #require(MCPExchange.decode(Data(line.utf8)).first, sourceLocation: sourceLocation)
    }

    /// Every response not read yet, once the server has exited.
    func remaining() -> [[String: Any]] {
        lines.update { pending in
            defer { pending = [] }
            return pending.compactMap { try? MCPExchange.decode(Data($0.utf8)).first }
        }
    }

    /// Opens `gate` for the fake walk.
    func open(_ gate: Gate) {
        events.update { _ = $0.open.insert(gate) }
    }

    /// Waits until the fake walk has done `step`.
    func until(_ step: Step) async throws {
        _ = try await events.wait("the fake walk to reach \(step)") { $0.done.contains(step) ? true : nil }
    }

    /// Closes the server's input: EOF.
    func closeInput() throws {
        let wasClosed = inputClosed.update { closed in
            defer { closed = true }
            return closed
        }
        guard !wasClosed else { return }
        try input.fileHandleForWriting.close()
    }

    /// Whether the server exits within `seconds` of wall time.
    func serverExits(within seconds: TimeInterval = Watched<Events>.limit) async -> Bool {
        await (try? events.wait("the server to exit", within: seconds) { $0.serverExited ? true : nil }) != nil
    }

    /// Whether the server writes nothing for `seconds` of wall time: the evidence that a response is held back, which no event can give.
    func staysQuiet(for seconds: TimeInterval) async -> Bool {
        await (try? lines.wait("a response from the server", within: seconds) { $0.isEmpty ? nil : true }) == nil
    }

    /// Lets everything end: every gate open, the clock released, the input closed; then a bounded wait for the server.
    private func tearDown(sourceLocation: SourceLocation) async {
        events.update { $0.open = Set(Gate.allCases) }
        clock.release()
        try? closeInput()
        let exited = await serverExits()
        output.fileHandleForReading.readabilityHandler = nil
        if !exited {
            Issue.record("the server did not exit within \(Watched<Events>.limit) s of its teardown", sourceLocation: sourceLocation)
        }
    }
}

extension BoundedServerRig {
    /// Where the fake walk waits for the test.
    enum Gate: CaseIterable, Sendable {
        /// Before the walk claims and begins its file.
        case begin
        /// Before it moves from step 2 to step 3, when it ``FakeWalk/advances``.
        case advance
        /// Before it returns.
        case end
    }

    /// What the fake walk has done.
    enum Step: Sendable {
        case began, advanced, endedFile, returned
    }

    struct Events {
        var open: Set<Gate> = []
        var done: Set<Step> = []
        var walkReturned = false
        var serverExited = false
        /// Whether the walk had returned when the server's `run` did.
        var serverExitedAfterWalk = false
    }

    /// A walk that begins a progress file `<stem>.json` in step 2 of 5 on `home`, and returns ``answer`` once ``Gate/end`` is open.
    struct FakeWalk: Sendable {
        var stem = "fake"
        var startedAt = Date(timeIntervalSince1970: 1_700_000_000.123)
        /// Waits for ``Gate/begin`` before the claim.
        var holdsBegin = false
        /// Moves to step 3 once ``Gate/advance`` is open.
        var advances = false
        /// Ends the file `failed` before it waits for ``Gate/end``, as a real walk's file goes final before it returns.
        var endsFileFirst = false
        var answer = MCPExchange.answer
        /// How long a gate is waited for before the walk returns regardless, so a rig torn down by a crash still lets its thread go.
        static let gateLimit: TimeInterval = 30

        func run(in directory: URL, events: Watched<Events>, started: SimWalkMCPServer.WalkStarted) -> Answer {
            if holdsBegin {
                pass(.begin, events)
            }
            let url = ProgressLocation.progressURL(session: stem, in: directory)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let writer = ProgressWriter(url: url, clock: { [startedAt] in startedAt }, pid: getpid())
            writer.begin(tool: "walk")
            writer.commit {
                $0.phase = .running
                $0.matches = WalkProgress.Matches(planned: 5)
                $0.currentStep = WalkProgress.CurrentStep(index: 2, total: 5)
                $0.currentStep?.screen = "home"
            }
            started(stem, writer.current)
            events.update { _ = $0.done.insert(.began) }
            if advances {
                pass(.advance, events)
                writer.commit { $0.currentStep = WalkProgress.CurrentStep(index: 3, total: 5) }
                events.update { _ = $0.done.insert(.advanced) }
            }
            if endsFileFirst {
                writer.finish(.failed, error: "the file's own ending")
                events.update { _ = $0.done.insert(.endedFile) }
            }
            pass(.end, events)
            events.update {
                $0.walkReturned = true
                $0.done.insert(.returned)
            }
            return answer
        }

        private func pass(_ gate: Gate, _ events: Watched<Events>) {
            _ = events.block(within: Self.gateLimit) { $0.open.contains(gate) ? true : nil }
        }
    }
}
