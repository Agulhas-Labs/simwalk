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

    /// `session` is whose Claude Code session this server was started for, read from the environment by the face that starts it — a parameter here so a test can assert the log line without setting one.
    public init(
        input: FileHandle,
        output: FileHandle,
        log: @escaping @Sendable (String) -> Void,
        usage: UsageLog?,
        session: String?,
        answering: @escaping AnswerProvider
    ) {
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
        let reader = FileHandleLines(reading: input) { [inFlight] line in inFlight.hear(line) }
        self.reader = reader
        for await line in reader.lines {
            let trimmed = line.trimmed
            guard !trimmed.isEmpty else { continue }
            handle(line: trimmed)
        }
        self.reader = nil
    }
}

public extension SimWalkMCPServer {
    /// What a verb and its argument vector answer — the CLI's own commands, wired in by the executable target — given what a client's cancel of the call raises.
    typealias AnswerProvider = @Sendable (SimWalkTool, [String], Cancellation) throws -> Answer
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
            emit(resultID: id, result: [
                "protocolVersion": requested,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": SimWalkPaths.binaryName, "version": SimWalkVersion.current],
            ])
        case "notifications/initialized", InFlightRequest.cancelledMethod:
            // A cancel was acted on as it was read (`InFlightRequest`); by the time it is handled here, the call it named has been answered or dropped.
            break
        case "ping":
            guard let id else { return }
            emit(resultID: id, result: [String: Any]())
        case "tools/list":
            guard let id else { return }
            emit(resultID: id, result: ["tools": MCPToolCatalog.tools])
        case "tools/call":
            guard let id else { return }
            handleToolCall(id: id, params: message["params"] as? [String: Any] ?? [:])
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
        defer { inFlight.finish() }
        // Cancelled while still queued behind another call (SimWalk#85): the tool never runs, nothing is answered, and
        // nothing is recorded — no call was made, unlike one cancelled mid-run.
        guard !cancellation.isCancelled else { return }
        do {
            let invocation = try MCPToolInvocation(tool: name, arguments: arguments)
            tool = invocation.logName
            target = invocation.target.isEmpty ? nil : invocation.target
            resolvedTool = invocation.tool
            let answer = try answering(invocation.tool, invocation.argumentVector, cancellation)
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

    /// The kind an unmapped failure over `tool` falls back to — used only when the error has no kind of its own, which is what keeps a classified refusal from being overwritten by it.
    ///
    /// The same rule the CLI's `TimedCall` follows at its own call sites: by the time `answering` runs, `MCPToolInvocation` has already checked the argument, so a failure it did not itself classify is that tool's own machinery, not a caller's mistake. `walk`'s machinery is the runner; `validate`, `inspect`, `audit` and `diff` run nothing but this tool's own code over an argument already checked, so theirs is `tool-error`. A call that never resolved to a tool is `MCPToolInvocation` refusing, which states its own kind on every error it throws — anything else escaping before resolution would be this server's own code, and is `tool-error` for the same reason.
    ///
    /// Never `nil`: an unmapped failure that recorded no kind would reach `simwalk usage` as `unclassified`, which is the gap a default exists to close.
    static func defaultFailureKind(for tool: SimWalkTool?) -> UsageFailureKind {
        switch tool {
        case .walk, .session: .runnerFailed
        case .validate, .inspect, .audit, .diff, .oracle, .mirror, nil: .toolError
        }
    }

    /// One log line per call, written before the response is emitted.
    ///
    /// The ordering matters one way only: a slow or failing log write can delay a response but can never corrupt one, and what is recorded is what happened rather than what was about to.
    func record(tool: String, target: String?, since started: ContinuousClock.Instant, err: String?, saving: ContextSaving?, kind: UsageFailureKind? = nil) {
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

    /// The protocol revision answered when a client names none.
    static var protocolVersion: String {
        "2025-06-18"
    }
}
