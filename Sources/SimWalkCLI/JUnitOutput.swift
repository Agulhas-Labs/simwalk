//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore

/// A command's `--junit <file>`: where the report goes, and the report the command's body leaves for ``TimedCall`` to write once the answer is computed.
///
/// A class because the body that builds the report and the call that writes it are two closures' distance apart. Writing is the call's, after the answer exists, so the exit code is the answer's whatever happens here; a write that fails qualifies the answer instead (`JUnit file not written: …`), and one after a refusal is stated beside it.
final class JUnitOutput {
    static let help = ArgumentHelp("Also write the result as JUnit XML to this file, for a CI test reporter: one test case per screen × state (walk), per flag (diff), per finding (audit) or per figure × state (oracle). The directory must exist. Exit codes are unchanged.", valueName: "file")

    let path: String
    let command: String
    /// Set by the command's body once it has the result; left `nil` when the command refused.
    var report: JUnitReport?

    init(path: String, command: String) {
        self.path = path
        self.command = command
    }

    /// The output for an optional `--junit` value.
    static func make(_ path: String?, command: String) -> JUnitOutput? {
        path.map { JUnitOutput(path: $0, command: command) }
    }

    /// Refuses a `--junit` path that is empty, is an existing directory, or whose directory does not exist, before any work is done.
    static func validate(_ path: String?) throws {
        guard let path else { return }
        guard !path.isEmpty else {
            throw ValidationError("--junit needs a file path, and got an empty one")
        }
        guard !JUnitFile.isDirectory(path) else {
            throw ValidationError("--junit \(path): that is a directory — name the file to write inside it")
        }
        guard JUnitFile.parentExists(of: path) else {
            throw ValidationError("--junit \(path): its directory does not exist — create it first, so a typo does not cost the run")
        }
    }

    /// Writes the report beside a computed answer; a failed write qualifies the answer.
    func finish(_ answer: Answer) -> Answer {
        guard let report else { return answer }
        do {
            try JUnitFile.write(report.holding(answer.verdict), to: path)
            return answer
        } catch {
            return answer.qualified(by: "JUnit file not written: \(error.localizedDescription)")
        }
    }

    /// Writes the refusal as one `<error>` case; the failure to, if any, as a line to print beside the refusal.
    func finish(refusal reason: String) -> String? {
        do {
            try JUnitFile.write(.refusal(command: command, reason: reason), to: path)
            return nil
        } catch {
            return "JUnit file not written: \(error.localizedDescription)"
        }
    }
}
