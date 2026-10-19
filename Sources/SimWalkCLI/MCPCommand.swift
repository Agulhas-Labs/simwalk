//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore
import SimWalkMCP

/// `simwalk mcp` — the MCP stdio server, for a coding agent rather than a person.
///
/// Nothing is printed here. The server owns stdout for the length of the session, and this command's only job is to hand it the three things it cannot find for itself: the streams, the log to record into, and the session the calls belong to.
struct MCPCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "mcp",
            abstract: "Run the MCP stdio server (JSON-RPC on stdin/stdout; diagnostics on stderr).",
            discussion: """
            Serves walk, validate, inspect, audit, diff, oracle, session and mirror as MCP tools (and walk_status to a bounded client), each answering exactly what the \
            matching CLI verb prints. Register it with `simwalk install-hook`, or by hand with \
            `claude mcp add --transport stdio --scope user simwalk -- <path to simwalk> mcp`.
            """
        )
    }

    func run() async {
        // Before anything else: this process may outlive the file it was launched from, and a walk it serves
        // hours later has to build the runner installed with *this* binary, not with whatever replaced it.
        LaunchedBinary.capture()
        let server = SimWalkMCPServer(
            input: FileHandle.standardInput,
            output: FileHandle.standardOutput,
            log: StandardStreams.emitError,
            usage: .standard(),
            // Claude Code puts the session id in the server's environment, which is what lets the status
            // line price this session's calls and nobody else's. Absent when the server is run by hand,
            // and a call recorded with no session is simply a call no status line claims.
            session: ProcessInfo.processInfo.environment["CLAUDE_CODE_SESSION_ID"],
            answering: { try MCPToolRunner.answer(tool: $0, arguments: $1, cancellation: $2, started: $3) },
            environment: ProcessInfo.processInfo.environment
        )
        await server.run()
    }
}
