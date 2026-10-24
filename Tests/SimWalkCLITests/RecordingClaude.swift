//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// A `claude` that records every run and keeps the user-scope server in a scratch `.claude.json` the way `claude mcp add` and `remove` would, so the install's read-back of that file sees what it did. A `remove` with no `--scope` takes a project's local-scope server of that name first, as `claude` does from inside that project.
///
/// What this tool asks of `claude` is a command line, and the two things most easily got wrong about it are invisible from watching an install succeed: that the removal comes first, and that `--scope` sits before the `--`. Both are only checkable by looking at the vectors, which is why running a process is a seam rather than a call.
final class RecordingClaude: ClaudeMcpRunner, @unchecked Sendable {
    private let lock = NSLock()
    private let config: URL
    private let addSucceeds: Bool
    private var recorded: [[String]] = []

    /// `addSucceeds: false` makes `mcp add` fail and write nothing.
    init(config: URL, addSucceeds: Bool = true) {
        self.config = config
        self.addSucceeds = addSucceeds
    }

    /// Every run's arguments, in order.
    var vectors: [[String]] {
        lock.withLock { recorded }
    }

    /// The runs that registered a server.
    var adds: [[String]] {
        vectors.filter { $0.prefix(2) == ["mcp", "add"] }
    }

    func run(_ arguments: [String]) throws -> Subprocess.Output? {
        lock.withLock {
            recorded.append(arguments)
            var object = (try? JSONSerialization.jsonObject(with: Data(contentsOf: config))) as? [String: Any] ?? [:]
            var servers = object["mcpServers"] as? [String: Any] ?? [:]
            switch Array(arguments.prefix(2)) {
            case ["mcp", "add"]:
                guard addSucceeds else {
                    return Subprocess.Output(succeeded: false, standardOutput: "", standardError: "already registered under that name")
                }
                guard let separator = arguments.firstIndex(of: "--") else {
                    return Subprocess.Output(succeeded: false, standardOutput: "", standardError: "no separator")
                }
                let command = arguments[(separator + 1)...]
                servers[arguments[separator - 1]] = ["type": "stdio", "command": command.first ?? "", "args": Array(command.dropFirst())]
            case ["mcp", "remove"] where !arguments.contains("--scope"):
                if var projects = object["projects"] as? [String: Any],
                   let key = projects.first(where: { (($0.value as? [String: Any])?["mcpServers"] as? [String: Any])?[arguments[2]] != nil })?.key,
                   var project = projects[key] as? [String: Any],
                   var local = project["mcpServers"] as? [String: Any]
                {
                    local.removeValue(forKey: arguments[2])
                    project["mcpServers"] = local
                    projects[key] = project
                    object["projects"] = projects
                } else if servers.removeValue(forKey: arguments[2]) == nil {
                    return Subprocess.Output(succeeded: false, standardOutput: "", standardError: "No MCP server named \"\(arguments[2])\"")
                }
            case ["mcp", "remove"]:
                guard servers[arguments[2]] != nil else {
                    return Subprocess.Output(succeeded: false, standardOutput: "", standardError: "No MCP server named \"\(arguments[2])\"")
                }
                servers.removeValue(forKey: arguments[2])
            default:
                return Subprocess.Output(succeeded: false, standardOutput: "", standardError: "unexpected")
            }
            object["mcpServers"] = servers
            try? JSONSerialization.data(withJSONObject: object).write(to: config)
            return Subprocess.Output(succeeded: true, standardOutput: "done")
        }
    }
}
