//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore

/// Runs one subcommand's work, prints its answer, records it in the usage log, and turns the answer's own verdict into the exit code.
///
/// Every subcommand goes through here so the four things that must be uniform stay uniform: an answer goes to stdout and a refusal to stderr, the exit code is the one the verdict names, both are logged, and a saving is recorded where the answer measured one. `ExitCode` is thrown rather than the original error because ArgumentParser prints a thrown error itself — which would repeat on stdout's sibling stream what has already been written to stderr in the tool's own words.
///
/// **The exit code is read off the answer rather than decided here or at the call site.** Each command used to compute its own qualification and throw its own code beside a summary that stated the qualification separately — two statements of one judgement, kept in step by hand, which is how `bundle inspect` came to print a bundle's shortfall and exit 0 over it. `AnswerVerdict` is now the single value, and this is the one place it becomes a process's exit status.
///
/// The log and the two streams are parameters with defaults rather than hard-wired calls, because the contract this type exists to hold is exactly the one a test has to be able to observe: which stream, which exit, which log line, and that a log that cannot be written changes none of the other three.
///
/// **`refusalClosing` is a line a thrown error's output ends with**, for the one caller whose answers all end with it: `device walk`, the alias, says it is `walk --device` now on a refusal as it does on an answer (SimWalk#116). It is not part of the logged reason.
///
/// **`log` is optional, and `usage` is why.** A verb that reads the log must not write to it, or a machine whose usage is checked daily reports checking as its most-used verb — but it still owes a caller the other three guarantees, so it goes through here with `nil` rather than around here with none of them. Passing no log suppresses the record and nothing else.
///
/// **The call is attributed to a Claude Code session when a hook says whose it is (SimWalk#14).** A process run from an agent's shell has no session of its own, so it claims the slip ``CallAttribution`` holds for its own arguments — as the call *starts*, since a walk runs for minutes and the slip is claimable for two — and the line it logs carries that session. Beside a log only: the slip lives next to the log it tags, and `usage`, which logs nothing, claims nothing. `arguments` is the process's own `argv` in normal use, and a parameter so a test can state it.
///
/// **`defaultFailureKind` is what a call site falls back to when the thrown error has no opinion of its own** (``UsageFailureKind/of(_:)`` returns `nil`) — a raw Foundation error from one of this command's own file writes, say, rather than a type this codebase has classified. It never overrides an error that has one. **Every command states its own, and there is no default to forget**: `install-hook` and `uninstall-hook` pass `.setupFailed`, since an unmapped failure there is Claude Code's own configuration or this tool's registration files, never a caller's argument; `walk` passes `.runnerFailed`, for the same reason one level down; `validate`, `bundle inspect` and `bundle audit` pass `.toolError`, because every failure of their argument is already a classified type (`WalkbookLoadError`, `CaptureBundleError` — a tree the runner wrote that does not decode included, which is `runner-failed` on its own account) and what is left is their own code. An optional parameter defaulting to `nil` let three verbs record no kind at all, which `simwalk usage` reads as `unclassified`.
struct TimedCall {
    static func run(
        tool: String,
        target: String?,
        log: UsageLog? = .standard(),
        emit: (String) -> Void = StandardStreams.emit,
        emitError: (String) -> Void = StandardStreams.emitError,
        defaultFailureKind: UsageFailureKind,
        arguments: [String] = Array(CommandLine.arguments.dropFirst()),
        isStdoutPiped: () -> Bool = StandardStreams.isStdoutPiped,
        refusalClosing closing: String? = nil,
        body: () throws -> Answer
    ) throws {
        let started = ContinuousClock.now
        let session = log.flatMap {
            CallAttribution(beside: $0).take(arguments: arguments, workingDirectory: FileManager.default.currentDirectoryPath)
        }
        let call = Call(tool: tool, target: target, started: started, session: session)
        let answer: Answer
        do {
            answer = try body()
        } catch {
            let reason = String(describing: error)
            emitError(([AnswerVerdict.refused(reason).line] + [closing].compactMap(\.self)).joined(separator: "\n"))
            record(log, of: call, err: reason, saving: nil, kind: .of(error) ?? defaultFailureKind)
            // Lost focus is the one refusal a caller should retry, so it alone has an exit of its own.
            let exitCode = error is MirrorFocusRefusal ? AnswerVerdict.notFrontmostExitCode : AnswerVerdict.refusedExitCode
            warnIfPiped(exitCode: exitCode, isStdoutPiped: isStdoutPiped, emitError: emitError)
            throw ExitCode(exitCode)
        }
        emit(answer.text)
        record(log, of: call, err: nil, saving: answer.saving)
        // Thrown after the answer is printed and logged, so the report a human reads is unchanged and only
        // the exit code differs. A walk that refused a screen is not a failed *call* — the bundle is
        // written, honest and readable — which is why a qualification has its own code: a caller can tell
        // "the tool refused" from "the tool worked and the app did not have what was asked for", and those
        // want different responses from a pipeline.
        guard answer.verdict.exitCode == 0 else {
            warnIfPiped(exitCode: answer.verdict.exitCode, isStdoutPiped: isStdoutPiped, emitError: emitError)
            throw ExitCode(answer.verdict.exitCode)
        }
    }

    /// `simwalk walk … | tail` reports `tail`'s exit 0 over a walk that exited 2, since a pipeline's status is its last command's and a caller reading `$?` never sees this process's own (SimWalk#40).
    ///
    /// Piping is the one case worth a nudge: stdout carries the answer to whatever comes next in the pipe, but stderr still reaches the terminal directly, so this line survives even where the answer itself does not.
    private static func warnIfPiped(exitCode: Int32, isStdoutPiped: () -> Bool, emitError: (String) -> Void) {
        guard isStdoutPiped() else { return }
        emitError("exit \(exitCode) — read ${PIPESTATUS[0]} (bash) / ${pipestatus[1]} (zsh), not $?")
    }

    /// Whether the call succeeded is read off `err` rather than passed beside it: here they are the same fact — a refusal always carries its reason and an answer never does — and two parameters saying one thing is a way for a log line to claim a success with a reason attached.
    private static func record(
        _ log: UsageLog?,
        of call: Call,
        err: String?,
        saving: ContextSaving?,
        kind: UsageFailureKind? = nil
    ) {
        guard let log else { return }
        let elapsed = ContinuousClock.now - call.started
        let milliseconds = Int(elapsed / .milliseconds(1))
        log.record(tool: call.tool, target: call.target, milliseconds: milliseconds, succeeded: err == nil, err: err, saving: saving, session: call.session, kind: kind)
    }
}

extension TimedCall {
    /// What a call is before it has an outcome: the tool and target it is logged under, when it started, and the session it is attributed to.
    private struct Call {
        let tool: String
        let target: String?
        let started: ContinuousClock.Instant
        let session: String?
    }
}
