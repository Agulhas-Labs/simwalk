//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkDriver
import SimWalkMCP

/// Claude Code's own CLI, as this tool drives it: finding it, and registering or removing the MCP server at user scope.
///
/// The registration is `claude`'s to make and not this tool's to hand-write, for the same reason the walk shells out to `xcodebuild` — its file format is its own, and a tool that writes another's configuration by hand is one that will eventually write last year's format into it.
///
/// **What it runs is injected**, so the argument vector is checkable without a `claude` on the machine. Two things about that vector are load-bearing and neither is visible from watching an install succeed: the removal that has to come first, and where `--scope` sits.
struct ClaudeCommandLine {
    let executable: String
    private let run: Run

    init(executable: String, run: @escaping Run = { try Shell().run($0, $1) }) {
        self.executable = executable
        self.run = run
    }

    /// Claude Code's CLI on this machine, or `nil` when there is none.
    ///
    /// A PATH walk rather than a `which` subprocess: the question is exactly "would running `claude` find something", and asking a shell to answer it costs a process and can be answered by a function or an alias this tool could not then execute.
    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        run: @escaping Run = { try Shell().run($0, $1) }
    ) -> ClaudeCommandLine? {
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("claude").path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return ClaudeCommandLine(executable: candidate, run: run)
            }
        }
        return nil
    }

    /// Registers this tool's MCP server at user scope, replacing any registration already under the name.
    ///
    /// **The removal first is not tidiness.** `claude mcp add` fails outright on a name already present, so an upgrade without it leaves the *old* binary registered while reporting a clean install — the exact failure the sibling tool learned the expensive way. Both removals are swallowed: either one failing means "it was not there", which is the outcome wanted.
    ///
    /// **A failure to launch `claude` at all is rewrapped as `HookInstallError`, not left as the `ShellError` it started out as.** `Shell.run`'s own classification is `.runnerFailed` — right for its usual callers, the walk runner's own machinery — but wrong here: `claude` being missing or broken is Claude Code's own configuration, the same shape as the refusal two lines down, and the usage log should not have to tell "the runner could not launch xcodebuild" from "install-hook could not launch claude" apart by reading the message.
    func registerServer(command: [String]) throws {
        _ = try? run(executable, ["mcp", "remove", SimWalkPaths.binaryName, "--scope", "user"])
        _ = try? run(executable, ["mcp", "remove", SimWalkPaths.binaryName])
        let arguments = Self.addArguments(command: command)
        let result: Shell.Result
        do {
            result = try run(executable, arguments)
        } catch {
            throw HookInstallError.claudeRefused(command: Self.rendered(arguments), reason: String(describing: error))
        }
        guard result.succeeded else {
            throw HookInstallError.claudeRefused(command: Self.rendered(arguments), reason: result.failureLine)
        }
    }

    /// Removes this tool's MCP server, reporting whether there was one to remove.
    ///
    /// Both scopes are tried because both are places a registration can be: user scope is where the install writes, and a scopeless entry is what an earlier `claude mcp add` by hand would have left.
    func removeServer() -> Bool {
        let scoped = (try? run(executable, ["mcp", "remove", SimWalkPaths.binaryName, "--scope", "user"]))?.succeeded ?? false
        let unscoped = (try? run(executable, ["mcp", "remove", SimWalkPaths.binaryName]))?.succeeded ?? false
        return scoped || unscoped
    }

    /// The registration's argument vector, in one place because the thing most easily got wrong about it is invisible once it is.
    ///
    /// `--scope` has to sit **before** the `--`, or `claude` stops reading its own options there and passes it through to the binary as an argument — registering a server at the default scope while the command line reads as though it asked for user scope.
    static func addArguments(command: [String]) -> [String] {
        ["mcp", "add", "--transport", "stdio", "--scope", "user", SimWalkPaths.binaryName, "--"] + command
    }

    /// The command line to register this tool by hand, for the refusal that has to name it.
    static func manualRegistration(command: [String]) -> String {
        rendered(addArguments(command: command))
    }

    private static func rendered(_ arguments: [String]) -> String {
        (["claude"] + arguments).joined(separator: " ")
    }
}

extension ClaudeCommandLine {
    /// How a child process is run — a seam, so what this asks of `claude` is checkable without one installed.
    typealias Run = (String, [String]) throws -> Shell.Result
}
