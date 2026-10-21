//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// The MCP stdio face: a newline-delimited JSON-RPC 2.0 loop over the same five verbs the CLI has.
///
/// **Stdout carries JSON-RPC and nothing else** — the rule the Brief carved in stone before any code existed, and one stray write corrupts the stream for the rest of the session. So diagnostics go through `log` (stderr in production), a walk's minutes of progress go nowhere near this handle, and the answer is written once, whole, when the walk is done.
///
/// The official Swift MCP SDK is not used, for the reason its sibling gives: the framing is a hundred lines and the SDK is pre-1.0 against a repo that pins exactly.
///
/// **The work is injected rather than reached for.** The verbs are ArgumentParser commands in the executable target, and the walk half of them spawns `xcodebuild` — neither of which this module can see, or should. So the server owns the protocol and the log line and is handed a function that turns a verb and an argument vector into an ``Answer``. That is also what makes the whole surface testable without a simulator.
public actor SimWalkMCPServer {
    private let input: FileHandle
    private let output: FileHandle
    private let log: @Sendable (String) -> Void
    private let usage: UsageLog?
    private let session: String?
    private let answering: AnswerProvider
    private var reader: FileHandleLines?
    /// The call being answered, which a client's cancel reaches from the reader's queue while this actor is busy answering it.
    private let inFlight = InFlightRequest()
    /// The client's name from `initialize` (or `SIMWALK_MCP_CLIENT`), which decides the mode.
    private var clientName: String?
    private let clientOverride: String?
    let budget: MCPCallBudget
    /// Seconds on a monotonic clock, and a suspension of so many seconds: every bounded wait goes through these, so a test never sleeps.
    private let clock: @Sendable () -> TimeInterval
    private let sleep: @Sendable (TimeInterval) async -> Void
    /// Every bounded walk this server started, for its lifetime: the last one may be running, the rest hold their answers.
    private var walks: [BoundedWalk] = []
    /// The bounded calls answering on tasks of their own, awaited at EOF.
    private var calls: [Task<Void, Never>] = []

    /// `session` is whose Claude Code session this server was started for, read from the environment by the face that starts it — a parameter here so a test can assert the log line without setting one.
    public init(
        input: FileHandle,
        output: FileHandle,
        log: @escaping @Sendable (String) -> Void,
        usage: UsageLog?,
        session: String?,
        answering: @escaping AnswerProvider,
        environment: [String: String] = [:],
        clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.clock = clock
        self.sleep = sleep
        clientOverride = environment["SIMWALK_MCP_CLIENT"]
        budget = MCPCallBudget(environment: environment)
        self.input = input
        self.output = output
        self.log = log
        self.usage = usage
        self.session = session
        self.answering = answering
    }

    /// Reads requests until the input closes, or until stdout dies under us.
    ///
    /// **A dead output ends the session from the write, not from the next read.** A flag checked at the top of this loop only helps if another request happens to arrive: a client that closes the pipe and then sends nothing would leave the server parked in `read(2)` for as long as the process lived. So the failed write finishes the reader itself and this loop falls out of its own accord.
    public func run() async {
        signal(SIGPIPE, SIG_IGN)
        if let warning = budget.warning {
            log(warning)
        }
        let reader = FileHandleLines(reading: input) { [inFlight] line in inFlight.hear(line) }
        self.reader = reader
        for await line in reader.lines {
            let trimmed = line.trimmed
            guard !trimmed.isEmpty else { continue }
            handle(line: trimmed)
        }
        self.reader = nil
        // EOF: the bounded calls answer within their budget, and the process exits only once every walk thread has returned.
        for call in calls {
            await call.value
        }
        for walk in walks {
            await walk.untilEnded()
        }
    }
}

public extension SimWalkMCPServer {
    /// What a verb and its argument vector answer — the CLI's own commands, wired in by the executable target — given what a client's cancel of the call raises.
    ///
    /// The fourth argument is how a walk reports the progress file it claimed and began — its stem and the progress as begun — which is what a bounded server forms the walk's handle from.
    typealias AnswerProvider = @Sendable (SimWalkTool, [String], Cancellation, @escaping WalkStarted) throws -> Answer

    /// A walk's report of its claimed progress-file stem and the progress as begun (its `pid` and `startedAt`).
    typealias WalkStarted = @Sendable (_ stem: String, _ progress: WalkProgress) -> Void
}

private extension SimWalkMCPServer {
    /// Reads one line and answers it, or says which of the three ways it was not a request.
    ///
    /// The three are separate codes because they send a client somewhere different: `-32700` is "these bytes are not JSON", `-32600` is "this is JSON and it is not a request" — a bare array, an object with no `method` — and `-32601` is "this is a request for something I do not serve". Collapsing the middle one into either of its neighbours tells a client to go and look at its serialiser when the shape is what is wrong, or at its method name when there is not one.
    func handle(line: String) {
        guard let data = line.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data)
        else {
            emit(errorID: NSNull(), code: -32700, message: "parse error")
            return
        }
        guard let message = parsed as? [String: Any] else {
            emit(errorID: NSNull(), code: -32600, message: "invalid request: a request is a JSON object")
            return
        }
        // A message with no id is a notification, and the protocol forbids answering one whatever the method.
        let id = message["id"]
        guard let method = message["method"] as? String else {
            // Not a notification either — a notification is a request without an id, not one without a
            // method — so it is answered, with a null id where the message carried none to echo.
            emit(errorID: id ?? NSNull(), code: -32600, message: "invalid request: no method")
            return
        }
        switch method {
        case "initialize":
            guard let id else { return }
            let params = message["params"] as? [String: Any]
            let requested = params?["protocolVersion"] as? String ?? Self.protocolVersion
            clientName = (params?["clientInfo"] as? [String: Any])?["name"] as? String
            var result: [String: Any] = [
                "protocolVersion": requested,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": SimWalkPaths.binaryName, "version": SimWalkVersion.current],
            ]
            if mode == .bounded {
                result["instructions"] = MCPInstructions.text
            }
            emit(resultID: id, result: result)
        case "notifications/initialized", InFlightRequest.cancelledMethod:
            // A cancel was acted on as it was read (`InFlightRequest`); by the time it is handled here, the call it named has been answered or dropped.
            break
        case "ping":
            guard let id else { return }
            emit(resultID: id, result: [String: Any]())
        case "tools/list":
            guard let id else { return }
            emit(resultID: id, result: ["tools": MCPToolCatalog.tools(for: mode)])
        case "tools/call":
            guard let id else { return }
            let params = message["params"] as? [String: Any] ?? [:]
            guard mode == .bounded else {
                // Claude Code: one call at a time, in arrival order, as always.
                handleToolCall(id: id, params: params)
                return
            }
            // A bounded client: each call on a task of its own, so a walk waiting out its budget leaves the actor free.
            calls.append(Task { await self.answerBounded(id: id, params: params) })
        default:
            if let id {
                emit(errorID: id, code: -32601, message: "method not found: \(method)")
            }
        }
    }

    /// Answers one tool call, and records it whether it answered or refused.
    ///
    /// A refusal comes back as a tool result marked `isError` rather than as a JSON-RPC error, in the same three words the CLI writes to stderr: the call was well formed and the tool has something to say about why it cannot answer, which is a thing the model reads rather than a protocol fault.
    ///
    /// **A call the client cancelled while it ran is recorded and not answered**: the protocol says a receiver should not respond to a cancelled request. A walk is not stopped by the cancel — it ends its progress file `failed` / `cancelled` and carries on to its end (SimWalk#83).
    func handleToolCall(id: Any, params: [String: Any]) {
        let name = params["name"] as? String ?? ""
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        let started = ContinuousClock.now
        // Named before the call resolves, for the case it never does: a call naming a tool this server does
        // not serve is still a call the machine was asked to make, and a log that dropped it would report a
        // model guessing at a name as a model that had stopped calling. A `step` that fails to resolve —
        // `step: 0`, `step: "-1"` or `step: true`, none of them a position or an id — is still a
        // screen-scoped attempt, so it is named as one before `MCPToolInvocation` ever gets to refuse it.
        var tool = name == SimWalkTool.inspect.rawValue && arguments["step"] != nil ? BundleScreenQuery.logName : name
        var target: String?
        // `nil` until an invocation resolves one — a call that never gets that far (an unknown tool, a bad
        // argument) is `MCPToolInvocation` refusing, which states `.inputRefused` on every error it throws.
        var resolvedTool: SimWalkTool?
        let cancellation = inFlight.start(id: id)
        defer { inFlight.finish(id: id) }
        // Cancelled while still queued behind another call (SimWalk#85): the tool never runs, nothing is answered, and
        // nothing is recorded — no call was made, unlike one cancelled mid-run.
        guard !cancellation.isCancelled else { return }
        do {
            let invocation = try MCPToolInvocation(tool: name, arguments: arguments, mode: mode)
            tool = invocation.logName
            target = invocation.target.isEmpty ? nil : invocation.target
            resolvedTool = invocation.tool
            let answer = try answering(invocation.tool, invocation.argumentVector, cancellation) { _, _ in }
            record(tool: tool, target: target, since: started, err: nil, saving: answer.saving)
            guard !cancellation.isCancelled else { return }
            emit(resultID: id, text: answer.text, isError: false)
        } catch {
            let reason = String(describing: error)
            record(tool: tool, target: target, since: started, err: reason, saving: nil, kind: .of(error) ?? Self.defaultFailureKind(for: resolvedTool))
            guard !cancellation.isCancelled else { return }
            emit(resultID: id, text: AnswerVerdict.refused(reason).line, isError: true)
        }
    }

    /// Answers one call from a bounded client: the busy rule, `walk` off the actor within the budget, `walk_status`, and every other tool as ``handleToolCall(id:params:)`` answers it.
    func answerBounded(id: Any, params: [String: Any]) async {
        let name = params["name"] as? String ?? ""
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        guard let invocation = try? MCPToolInvocation(tool: name, arguments: arguments, mode: mode),
              [.walk, .session, .mirror, .walkStatus].contains(invocation.tool)
        else {
            return handleToolCall(id: id, params: params)
        }
        let started = ContinuousClock.now
        let target = invocation.target.isEmpty ? nil : invocation.target
        if invocation.tool == .walkStatus {
            let cancellation = inFlight.start(id: id)
            defer { inFlight.finish(id: id) }
            guard !cancellation.isCancelled else { return }
            let status = await walkStatus(invocation.target)
            // A cancelled status read did no device work, unlike a cancelled `walk`, whose thread logs the walk it did: it records nothing.
            guard !cancellation.isCancelled else { return }
            record(tool: invocation.logName, target: target, since: started, err: status.isError ? status.text.removingPrefix(AnswerVerdict.refused("").line) : nil, saving: nil, kind: status.isError ? Self.defaultFailureKind(for: .walkStatus) : nil)
            return emit(resultID: id, text: status.text, isError: status.isError)
        }
        // In flight before the busy wait, so a cancel heard while it waits names this call: a cancelled call is not answered, not even
        // with the busy refusal, records nothing, and leaves no id behind for a later call to consume.
        let cancellation = inFlight.start(id: id)
        defer { inFlight.finish(id: id) }
        guard !cancellation.isCancelled else { return }
        // One device-touching walk at a time, judged from the in-process state; a walk that has not reported its handle yet does so within milliseconds.
        while let running = walks.last, running.ended == nil {
            guard let handle = running.handle else {
                await running.untilHandleOrEnd()
                continue
            }
            guard !cancellation.isCancelled else { return }
            let reason = "a walk is running (\(handle.text)); poll it with walk_status, then retry"
            record(tool: invocation.logName, target: target, since: started, err: reason, saving: nil, kind: .toolError)
            return emit(resultID: id, text: AnswerVerdict.refused(reason).line, isError: true)
        }
        guard !cancellation.isCancelled else { return }
        guard invocation.tool == .walk else {
            // `handleToolCall` starts the call itself: a cancel heard from here on is kept for that start to consume. Finish first, then
            // re-check, so a cancel heard before the finish is not lost between the guard above and the hand-over.
            inFlight.finish(id: id)
            guard !cancellation.isCancelled else { return }
            return handleToolCall(id: id, params: params)
        }
        let walk = BoundedWalk()
        walks.append(walk)
        start(walk, invocation, cancellation: cancellation, since: started)
        await walk.untilEnded(orAfter: budget.seconds, sleep: sleep)
        if walk.ended == nil {
            await walk.untilHandleOrEnd()
        }
        guard !cancellation.isCancelled else { return }
        let status = answer(for: walk)
        emit(resultID: id, text: status.text, isError: status.isError)
    }

    /// Runs the walk on a dedicated thread through the synchronous answering path, logging its one usage line when it ends.
    func start(_ walk: BoundedWalk, _ invocation: MCPToolInvocation, cancellation: Cancellation, since started: ContinuousClock.Instant) {
        let answering = answering
        let target = invocation.target.isEmpty ? nil : invocation.target
        let thread = Thread { [self] in
            do {
                let answer = try answering(invocation.tool, invocation.argumentVector, cancellation) { walk.started(stem: $0, progress: $1) }
                record(tool: invocation.logName, target: target, since: started, err: nil, saving: answer.saving)
                walk.end(BoundedWalk.Ended(text: answer.text, isError: false))
            } catch {
                let reason = String(describing: error)
                record(tool: invocation.logName, target: target, since: started, err: reason, saving: nil, kind: .of(error) ?? Self.defaultFailureKind(for: .walk))
                walk.end(BoundedWalk.Ended(text: AnswerVerdict.refused(reason).line, isError: true))
            }
        }
        thread.start()
    }

    /// The walk's held answer once it has ended, else its `running` line, rendered from its progress file — re-checked now, so a walk that ended at the budget is returned.
    func answer(for walk: BoundedWalk) -> WalkStatus {
        if let ended = walk.ended {
            return WalkStatus(text: ended.text, isError: ended.isError)
        }
        // Only reached once the walk has reported its start: every caller waits for the handle or the end first.
        guard let (handle, began) = walk.start else {
            return WalkStatus(text: AnswerVerdict.refused("the walk has not begun").line, isError: true)
        }
        return WalkStatus(text: WalkStatusReader.runningLine(handle, statusReader.progress(of: handle) ?? began), isError: false)
    }

    /// `walk_status`: this server's own walk from its in-process state, any other handle from the files.
    func walkStatus(_ handle: String) async -> WalkStatus {
        guard let walk = walks.first(where: { $0.handle?.text == handle }) else {
            return await statusReader.status(of: handle, budget: budget.seconds, clock: clock, sleep: sleep)
        }
        await walk.untilEnded(orAfter: budget.seconds, sleep: sleep)
        return answer(for: walk)
    }

    /// The reader for the progress files beside the usage log, where a walk's claim puts them.
    var statusReader: WalkStatusReader {
        WalkStatusReader(directory: usage?.directory ?? UsageLog.standard(environment: [:]).directory)
    }

    /// The kind an unmapped failure over `tool` falls back to — used only when the error has no kind of its own, which is what keeps a classified refusal from being overwritten by it.
    ///
    /// The same rule the CLI's `TimedCall` follows at its own call sites: by the time `answering` runs, `MCPToolInvocation` has already checked the argument, so a failure it did not itself classify is that tool's own machinery, not a caller's mistake. `walk`'s machinery is the runner; `validate`, `inspect`, `audit` and `diff` run nothing but this tool's own code over an argument already checked, so theirs is `tool-error`. A call that never resolved to a tool is `MCPToolInvocation` refusing, which states its own kind on every error it throws — anything else escaping before resolution would be this server's own code, and is `tool-error` for the same reason.
    ///
    /// Never `nil`: an unmapped failure that recorded no kind would reach `simwalk usage` as `unclassified`, which is the gap a default exists to close.
    static func defaultFailureKind(for tool: SimWalkTool?) -> UsageFailureKind {
        switch tool {
        case .walk, .session: .runnerFailed
        case .validate, .inspect, .audit, .diff, .oracle, .mirror, .walkStatus, nil: .toolError
        }
    }

    /// One log line per call, written before the response is emitted.
    ///
    /// The ordering matters one way only: a slow or failing log write can delay a response but can never corrupt one, and what is recorded is what happened rather than what was about to.
    nonisolated func record(tool: String, target: String?, since started: ContinuousClock.Instant, err: String?, saving: ContextSaving?, kind: UsageFailureKind? = nil) {
        guard let usage else { return }
        let elapsed = ContinuousClock.now - started
        usage.record(
            tool: tool,
            target: target,
            milliseconds: Int(elapsed / .milliseconds(1)),
            succeeded: err == nil,
            err: err,
            saving: saving,
            session: session,
            kind: kind
        )
    }

    // MARK: Emission (protocol JSON only)

    func emit(resultID: Any, text: String, isError: Bool) {
        emit(resultID: resultID, result: [
            "content": [["type": "text", "text": text]],
            "isError": isError,
        ])
    }

    func emit(resultID: Any, result: [String: Any]) {
        write(["jsonrpc": "2.0", "id": resultID, "result": result])
    }

    func emit(errorID: Any, code: Int, message: String) {
        write(["jsonrpc": "2.0", "id": errorID, "error": ["code": code, "message": message]])
    }

    /// Writes through the throwing API — the exception-raising `write(_:)` would kill the process the moment the client closes stdout, where here a dead pipe just ends the session.
    func write(_ payload: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: payload) else {
            log("simwalk mcp: failed to encode a response")
            return
        }
        data.append(0x0A)
        do {
            try output.write(contentsOf: data)
        } catch {
            // Ends the read loop rather than flagging it: there is nothing left to answer with, and the
            // half of the connection that would otherwise have to close first is the one still working.
            reader?.finish()
            log("simwalk mcp: stdout closed — shutting down (\(error))")
        }
    }

    /// The mode for this client: `SIMWALK_MCP_CLIENT`, when set, replaces the name `initialize` recorded.
    var mode: MCPClientMode {
        MCPClientMode(clientName: clientOverride ?? clientName)
    }

    /// The protocol revision answered when a client names none.
    static var protocolVersion: String {
        "2025-06-18"
    }
}

private extension String {
    /// `self` without a leading `prefix`; unchanged when it does not start with it.
    func removingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
