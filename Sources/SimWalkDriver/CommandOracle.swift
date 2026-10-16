//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// A value oracle that is an external command (Brief §2.3): SimWalk's side of the protocol, with nothing about any data source in it.
///
/// **The protocol.** One process per check, not per figure: every request is written to its stdin as one JSON line (`OracleRequest.jsonLine`), and it answers on stdout with one JSON object per line, in request order — `{"values": {"midnight": 3326, "rolling24h": 2703}, "unit": "count", "attribution": "free text"}`, or `{"error": "…"}` for a request it cannot answer. Batched because an oracle over a HealthKit store or a corpus pays its setup once, not once per figure per state.
///
/// **A timeout stops what the command started**, not only the command: `Process` on Darwin starts the child as the leader of a process group of its own and `terminate()` signals that group, so a script that runs `python3 query.py` without `exec` leaves nothing running past the bound (`anOracleThatTimesOutLeavesNothingItStartedRunning`). A grandchild that ignores `SIGTERM` does outlive it — `Shell` escalates to `SIGKILL` on the child alone.
///
/// **Every way it can fail is `failed`, never a verdict.** A timeout, a non-zero exit, output cut off, or a count of reply lines that is not the count of requests fails every request, naming why — replies are matched by order, so a short answer cannot be attributed to any of them; a line that does not parse fails its own request.
///
/// **Where the command runs.** `command[0]` absolute is run as written; relative with a `/` in it (`./oracle.sh`, `tools/oracle`) resolves against the walkbook's directory; a bare name (`python3`) is looked up on `PATH` through `/usr/bin/env`. The command's working directory is the walkbook's, so its arguments resolve there too.
public struct CommandOracle: ValueOracle {
    public let command: [String]
    public let directory: URL
    public let timeout: TimeInterval
    private let shell: Shell

    /// How long the whole batch may take before every request fails as timed out.
    public static let defaultTimeout: TimeInterval = 30

    public init(_ oracle: Walkbook.Oracle, walkbookDirectory: URL, timeout: TimeInterval = CommandOracle.defaultTimeout, shell: Shell = Shell()) {
        command = oracle.command
        directory = walkbookDirectory
        self.timeout = timeout
        self.shell = shell
    }

    public func answers(to requests: [OracleRequest]) -> [OracleAnswer] {
        guard !requests.isEmpty else { return [] }
        guard let (executable, arguments) = invocation else {
            return Self.failing(requests, "the walkbook's oracle names no command")
        }
        let input = Data(requests.map { $0.jsonLine + "\n" }.joined().utf8)
        let result: Shell.Result
        do {
            result = try shell.run(executable, arguments, timeout: timeout, input: input, workingDirectory: directory)
        } catch let ShellError.timedOut(_, seconds) {
            return Self.failing(requests, "it did not answer within \(String(format: "%g", seconds))s")
        } catch {
            return Self.failing(requests, "it could not be run: \(error)")
        }
        guard result.succeeded else {
            return Self.failing(requests, "it exited \(result.status): \(result.failureLine)")
        }
        guard !result.truncated else {
            return Self.failing(requests, "its output was cut off, so its replies cannot be matched to requests")
        }
        let lines = result.standardOutput.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.count == requests.count else {
            return Self.failing(requests, "it answered \(lines.count) line\(lines.count == 1 ? "" : "s") to \(requests.count) request\(requests.count == 1 ? "" : "s"), and replies are matched by order")
        }
        return lines.map(OracleAnswer.parsing)
    }

    /// The executable and arguments `command` runs as, resolved as the type's documentation says.
    var invocation: (String, [String])? {
        guard let first = command.first, !first.isEmpty else { return nil }
        let rest = Array(command.dropFirst())
        if first.hasPrefix("/") {
            return (first, rest)
        }
        if first.contains("/") {
            return (directory.appendingPathComponent(first).standardizedFileURL.path, rest)
        }
        return ("/usr/bin/env", [first] + rest)
    }

    private static func failing(_ requests: [OracleRequest], _ reason: String) -> [OracleAnswer] {
        requests.map { _ in .failed(reason: reason) }
    }
}
