//
// Copyright © Agulhas Labs
//

import Foundation

/// Refuses, once, a context's second distinct call that drives a simulator by hand in a repository whose walkbook already drives it — and says what one walk would have captured instead (SimWalk#12).
///
/// **Going around this tool was silent.** A builder hand-tapped seven screenshots with `xcrun simctl io … screenshot` where one `simwalk walk` of a field walkbook already covering that screen would have captured every screen in every state with a tree each, and the usage log had no line that day to say the tool had been passed over. sift answers the same habit with a refusal that names the index query and lets the identical re-run through; this is that, for a walkbook.
///
/// **Only where a walkbook loads.** A repository with none has nothing better to offer, so the hook is silent there. What counts as driving by hand: `simctl io <device> screenshot` and `simctl ui <device> appearance`, bare or behind `xcrun` (its own flags included), `timeout <duration>`, a loop or conditional's own keyword, or a `bash -c "…"` string; a third-party simulator CLI's `tap`; and the Xcode build MCP server's `screenshot`, `tap`, `swipe`, `touch` and `gesture` tools. That CLI's UI-describe command is AX probing, which SimWalk#12 names as legitimate — it is never refused. A shell call that also runs this tool is never refused — it is the advice being taken.
///
/// **It never stands in the way twice.** Probing an accessibility tree and a one-off capture are legitimate, so the refusal names the simulator command it is keyed on and says that command goes through when it is run again, alone or beside anything but another simulator command (SimWalk#80), and ``NudgeLedger`` keeps that promise; AX probing is pointed at `simwalk inspect`, which reads the tree without a screenshot. **Nor on a first call** (SimWalk#110): a context's first hand-driving call within the ledger's memory goes through, the next distinct one is refused once, and then the ledger's cap quiets it for a context that has heard it and chosen otherwise. A lone one-off capture was refused on the first try and cost a turn each time; a hand-tapped loop still hears it at its second capture.
public struct HandDrivingNudge {
    /// The refusal for `call`, as the `PreToolUse` output that carries it, or `nil` where the call goes through.
    ///
    /// `payload` is the call's own bytes, read again only for an MCP call, whose whole input is what makes it identical to another.
    static func respond(to call: PreToolUseHook.Call, payload: Data, ledger: NudgeLedger) -> String? {
        guard let refused = handDriving(call, payload: payload), let directory = call.workingDirectory else { return nil }
        let walkbooks = RepositoryWalkbooks.loaded(from: directory)
        // A subagent's payload carries its parent's session, so the agent is what keeps its re-runs and its cap its own.
        let context = call.agentID.map { "\(call.sessionID)-\($0)" } ?? call.sessionID
        guard !walkbooks.isEmpty, ledger.refuses(context: context, call: refused.key) else { return nil }
        return denial(reason: reason(offering: walkbooks, letThrough: refused.shellCommands))
    }

    /// The refusal's text: each walkbook with the command that walks it and what that captures, then the way through.
    ///
    /// `letThrough` is the simulator commands a shell call's allowance is keyed on, named so the re-run the refusal promises is the one it lets through (SimWalk#80); empty for an MCP call, which is keyed on the whole call.
    public static func reason(offering walkbooks: [RepositoryWalkbooks.Found], letThrough: [String] = []) -> String {
        let shown = walkbooks.prefix(shownWalkbooks)
        var lines = ["\(SimWalkPaths.binaryName): a walkbook here already drives this app, with a screenshot and an accessibility tree of every state:"]
        lines += shown.map { "  \(SimWalkPaths.binaryName) walk \($0.path)   (\(price($0)))" }
        if walkbooks.count > shown.count {
            lines.append("  … and \(walkbooks.count - shown.count) more in \(RepositoryWalkbooks.directory)/")
        }
        let reRun = letThrough.isEmpty
            ? "re-run the identical call: it goes through."
            : "re-run \(letThrough.map { "`\($0)`" }.joined(separator: " with ")), alone or beside anything but another simulator command: the allowance is keyed on \(letThrough.count == 1 ? "that command's" : "those commands'") own words, so it goes through."
        lines.append("Or the MCP `walk` tool with the same walkbook. For a one-off capture, \(reRun) For AX probing, `\(SimWalkPaths.binaryName) inspect --device <udid> --app <bundle id>` reads the running app's tree instead of a screenshot.")
        return lines.joined(separator: "\n")
    }

    /// What one walk of a walkbook captures, in the words a refusal prices it with.
    public static func price(_ walkbook: RepositoryWalkbooks.Found) -> String {
        "\(walkbook.screens) screen\(walkbook.screens == 1 ? "" : "s") / \(walkbook.states) state\(walkbook.states == 1 ? "" : "s") in one command, vs one turn per tap"
    }
}

private extension HandDrivingNudge {
    /// Walkbooks named one per line before the rest are counted.
    static var shownWalkbooks: Int {
        3
    }

    /// The Xcode build MCP server's tools that drive a simulator one gesture or one picture at a time.
    static var handDrivingTools: Set<String> {
        ["mcp__XcodeBuildMCP__screenshot", "mcp__XcodeBuildMCP__tap", "mcp__XcodeBuildMCP__swipe", "mcp__XcodeBuildMCP__touch", "mcp__XcodeBuildMCP__gesture"]
    }

    /// What a refused call is remembered by, and the simulator commands a refusal names as its way through.
    struct Refused {
        /// The ledger's key for the call.
        let key: String
        /// A shell call's simulator commands, which ``key`` is made of; empty for an MCP call.
        let shellCommands: [String]
    }

    /// What a refused call is remembered by, or `nil` when `call` does not drive a simulator by hand.
    ///
    /// A shell call by its simulator commands alone (or, where one still holds an unresolved `$` or backtick, by its whole command line with whitespace collapsed), each from `simctl` or that CLI's name on, as the shell will split it, and with the `$NAME`s the call itself has set spelled out — so the re-run goes through however it is spelled around them: a different build beside it, or none, a wrapper of `xcrun`, `timeout`, a loop or `bash -c`, other spacing or quoting, the variable or the value it holds (SimWalk#80). The whole command line was the key before, and a re-run that dropped an `ls` from it was refused again. An MCP call by its tool and its input in canonical form.
    static func handDriving(_ call: PreToolUseHook.Call, payload: Data) -> Refused? {
        if handDrivingTools.contains(call.toolName) {
            let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
            let input = (object?["tool_input"]).flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .fragmentsAllowed]) }
            return Refused(key: call.toolName + " " + (input.flatMap { String(bytes: $0, encoding: .utf8) } ?? ""), shellCommands: [])
        }
        guard call.toolName == "Bash", let command = call.toolInput?.command,
              TranscriptScan.invocations(in: command).isEmpty
        else {
            return nil
        }
        let driving = drivingCommands(in: command, variables: [:])
        if driving.isEmpty {
            return nil
        }
        // A `$` or backtick that survives expansion stands for something the call does not spell (a loop variable, `$(…)`, `read`, the environment), so two different commands could share these words: the whole command line keys it, as it did before #80.
        if driving.contains(where: { $0.contains("$") || $0.contains("`") }) {
            return Refused(key: command.split(whereSeparator: \.isWhitespace).joined(separator: " "), shellCommands: [])
        }
        return Refused(key: driving.joined(separator: "\n"), shellCommands: driving)
    }

    /// The simulator-driving commands a shell command line runs, in order, each as its words from `simctl` or that CLI's name on.
    ///
    /// A command made only of `NAME=value` words sets those names for the commands after it, as the shell does, and a `$NAME` or `${NAME}` set that way is spelled out; one the line has not set is kept as written, and a command still holding a `$` or backtick after that is not keyed by its words (``handDriving`` falls back to the whole command line, since a loop variable, `$(…)` or `read` stands for what the call does not spell). `variables` carries the names already set into a `bash -c` string.
    static func drivingCommands(in command: String, variables: [String: String]) -> [String] {
        var variables = variables
        var driving: [String] = []
        for words in TranscriptScan.commands(in: command) {
            if words.allSatisfy(TranscriptScan.isAssignment) {
                for word in words {
                    let equals = word.firstIndex(of: "=") ?? word.endIndex
                    variables[String(word[..<equals])] = expanding(String(word[word.index(after: equals)...]), with: variables)
                }
                continue
            }
            driving += drivingWords(words, variables: variables)
        }
        return driving
    }

    /// `word` with each `$NAME` or `${NAME}` in `variables` spelled out, and every other one left as written.
    static func expanding(_ word: String, with variables: [String: String]) -> String {
        guard word.contains("$"), !variables.isEmpty else { return word }
        return word.replacing(#/\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))/#) { match in
            (match.output.1 ?? match.output.2).flatMap { variables[String($0)] } ?? String(match.output.0)
        }
    }

    /// The `xcrun` flags that take a value of their own, so `--sdk iphonesimulator simctl …` still reaches `simctl`.
    static var xcrunFlagsTakingValue: Set<String> {
        ["--sdk", "--toolchain"]
    }

    /// The `timeout` flags that take a value of their own, so `timeout -s TERM 30 xcrun …` still reaches the duration.
    static var timeoutFlagsTakingValue: Set<String> {
        ["-s", "--signal", "-k", "--kill-after"]
    }

    /// The simulator commands one command's words run, each from `simctl` or that CLI's name on with `variables` spelled out: `simctl io <device> screenshot`, `simctl ui <device> appearance` (bare, behind `xcrun` with or without its own flags, behind `timeout <duration>`, or inside a `bash -c "…"` string read as a command line of its own), or that CLI's `tap`; empty for anything else.
    ///
    /// That CLI's UI-describe command is AX probing, not driving (SimWalk#37), and is never nudged. A `for`/`while`/`if` body's own words leave its keyword (`do`, `then`, `else`, `elif`) attached to the command that follows it, so that is stripped too.
    static func drivingWords(_ words: [String], variables: [String: String]) -> [String] {
        var words = words[...]
        let key = { (words: ArraySlice<String>) in
            ([executableName(words.first ?? "")] + words.dropFirst().map { expanding($0, with: variables) }).joined(separator: " ")
        }
        while let word = words.first.map(executableName) {
            switch word {
            case "do", "then", "else", "elif":
                words = words.dropFirst()
            case "xcrun":
                words = words.dropFirst()
                while let flag = words.first, flag.hasPrefix("-") {
                    words = words.dropFirst(xcrunFlagsTakingValue.contains(flag) ? 2 : 1)
                }
            case "timeout":
                words = words.dropFirst()
                while let flag = words.first, flag.hasPrefix("-") {
                    words = words.dropFirst(timeoutFlagsTakingValue.contains(flag) ? 2 : 1)
                }
                if words.first?.first?.isNumber == true {
                    words = words.dropFirst()
                }
            case "bash", "sh", "zsh":
                guard words.dropFirst().first == "-c", let script = words.dropFirst(2).first else { return [] }
                return drivingCommands(in: script, variables: variables)
            case "simctl":
                let drives = zip(words, words.dropFirst(2)).contains { ($0 == "io" && $1 == "screenshot") || ($0 == "ui" && $1 == "appearance") }
                return drives ? [key(words)] : []
            case "axe":
                return words.dropFirst().first == "tap" ? [key(words)] : []
            default:
                return []
            }
        }
        return []
    }

    /// A command word as the name of what it runs, however its path reaches it.
    static func executableName(_ word: String) -> String {
        word.split(separator: "/").last.map(String.init) ?? word
    }

    /// Claude Code's `PreToolUse` refusal, which it hands the model as the call's result; `nil` when it cannot be encoded, since a hook that prints what the harness cannot parse is worse than one that prints nothing.
    static func denial(reason: String) -> String? {
        let output: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return nil
        }
        return String(bytes: data, encoding: .utf8)
    }
}
