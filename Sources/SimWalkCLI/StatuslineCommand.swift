//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkMCP

/// `simwalk statusline` — the Claude Code status-line segment, fed the session JSON on stdin.
///
/// **It is not logged and it does not go through `TimedCall`**, for the reason `usage` does not record itself, doubled: it runs on every assistant message, so a line per render would swamp the log it is reporting on within an afternoon — and it prints one line to stdout or nothing at all, which is the whole of what Claude Code will display. There is no answer here to give a verdict to.
struct StatuslineCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "statusline",
            abstract: "Print this session's simwalk segment, for a Claude Code status line.",
            discussion: """
            Reads the status-line JSON on stdin and prints one line: what this session's walks saved, \
            how many calls it made, how many failed and how many were refused. Prints nothing when the session has made no \
            simwalk calls. Wire it up with `simwalk install-hook`. `--hide` silences it on this machine \
            without touching the registration; `--show` reverses that.
            """
        )
    }

    @Option(name: .customLong("transcript"), help: "Transcript to read, instead of the transcript_path in the stdin JSON.")
    var transcript: String?

    @Flag(name: .customLong("hide"), help: "Silence the segment on this machine. The registration stays, so upgrades cannot resurrect it.")
    var hide = false

    @Flag(name: .customLong("show"), help: "Show a hidden segment again.")
    var show = false

    func run() throws {
        if hide || show {
            try toggleVisibility()
            return
        }
        let payload = Self.payloadFromStandardInput()
        guard let path = transcript ?? payload?["transcript_path"] as? String else { return }
        let segment = StatuslineReport.standard().segment(transcriptPath: path, workingDirectory: Self.workingDirectory(in: payload))
        guard let segment else { return }
        StandardStreams.emit(segment)
    }

    /// The session's working directory from the status-line payload — `workspace.current_dir`, else `cwd` — or `nil` where it names none.
    static func workingDirectory(in payload: [String: Any]?) -> String? {
        let workspace = payload?["workspace"] as? [String: Any]
        return workspace?["current_dir"] as? String ?? payload?["cwd"] as? String
    }

    /// `--hide` / `--show`, each reporting whether it changed anything rather than claiming success blandly.
    private func toggleVisibility() throws {
        guard hide != show else {
            throw ValidationError("--hide and --show contradict each other; pass one.")
        }
        let visibility = StatuslineVisibility.standard()
        if hide {
            try StandardStreams.emit(visibility.hide()
                ? "status line hidden — the registration stays and prints nothing; `simwalk statusline --show` brings it back"
                : "status line already hidden")
        } else {
            try StandardStreams.emit(visibility.show()
                ? "status line restored — it prints again from the next session update"
                : "status line was not hidden")
        }
    }

    /// The status-line payload, or `nil` if stdin carries no usable JSON.
    ///
    /// Every failure here is silent on purpose: this runs on every assistant message, and a status line that prints a parse error into somebody's session on a malformed payload is worse than one that prints nothing.
    private static func payloadFromStandardInput() -> [String: Any]? {
        guard let data = try? FileHandle.standardInput.readToEnd(), !data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
