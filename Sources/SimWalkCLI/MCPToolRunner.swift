//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
import SimWalkCore
import SimWalkDriver
import SimWalkMCP

/// What an MCP verb answers: the CLI's own subcommand, parsed from the argument vector the invocation built.
///
/// **The two faces share the commands rather than the shape of them.** A second implementation of `walk` behind the MCP server would be a second set of defaults, a second `--settle` guard and a second idea of what an option is called, drifting apart the first time either side is touched. So the MCP face builds a command line, the subcommand parses it with its own definitions, and the answer that comes back is the one the CLI would have printed — including every refusal the command makes of its own arguments.
struct MCPToolRunner {
    /// `cancellation` is the client's cancel of this call, which ends a walk's progress file `failed` / `cancelled` (SimWalk#83), and a `session start`'s; no other verb writes one.
    ///
    /// `started` hears a walk's claimed progress-file stem and the progress as begun, before its target is resolved: what a bounded server forms the walk's handle from.
    static func answer(tool: SimWalkTool, arguments: [String], cancellation: Cancellation? = nil, started: SimWalkMCPServer.WalkStarted? = nil) throws -> Answer {
        try answer(tool: tool, arguments: arguments, environment: ProcessInfo.processInfo.environment, cancellation: cancellation, started: started)
    }

    /// The same answer with the environment a walk's progress file is placed from named, so a test refused partway through a walk writes beside a log it owns and never into the machine's own `~/.simwalk/progress`.
    ///
    /// `animationsLibrary` names the animations-off library a walk and a session start are offered, from the environment: the standard one unless a test hands its own, so no test compiles a library or reads the machine's `~/.simwalk` (SimWalk#154).
    static func answer(
        tool: SimWalkTool,
        arguments: [String],
        environment: [String: String],
        cancellation: Cancellation? = nil,
        started: SimWalkMCPServer.WalkStarted? = nil,
        walking: WalkSeams = WalkSeams(),
        animationsLibrary: ([String: String]) -> WalkCommand.AnimationsLibrary = { WalkCommand.standardAnimationsLibrary(environment: $0) }
    ) throws -> Answer {
        switch tool {
        case .walk: try parsed(WalkCommand.self, arguments).answer(environment: environment, cancellation: cancellation, started: started, shell: walking.shell, runner: walking.runner, builds: walking.builds, leases: walking.leases, animationsLibrary: animationsLibrary(environment))
        case .validate: try parsed(ValidateCommand.self, arguments).answer()
        case .inspect: try inspectAnswer(arguments)
        case .audit: try parsed(BundleAuditCommand.self, arguments).answer()
        case .diff: try parsed(BundleDiffCommand.self, arguments).answer()
        case .oracle: try parsed(BundleOracleCommand.self, arguments).answer()
        case .session: try sessionAnswer(arguments, cancellation: cancellation, shell: walking.shell, runner: walking.runner, builds: walking.builds, environment: environment, animationsLibrary: animationsLibrary(environment))
        case .mirror: try mirrorAnswer(arguments)
        case .walkStatus: throw MCPError(message: "walk_status is answered by the server, not the runner", kind: .toolError)
        }
    }

    /// `mirror`'s six actions: the vector leads with the action, spelled as the subcommand's own name, and the rest is that subcommand's command line — so each answers what `simwalk mirror <action>` prints, through the same `perform`.
    static func mirrorAnswer(_ arguments: [String], makeStepper: (MirrorCaptureStore) -> any MirrorStepping = MirrorStepOptions.liveStepper) throws -> Answer {
        let rest = Array(arguments.dropFirst())
        switch arguments.first {
        case MirrorReadCommand.configuration.commandName:
            return try parsed(MirrorReadCommand.self, rest).perform(makeStepper: makeStepper)
        case MirrorTapCommand.configuration.commandName:
            return try parsed(MirrorTapCommand.self, rest).perform(makeStepper: makeStepper)
        case MirrorSwipeCommand.configuration.commandName:
            return try parsed(MirrorSwipeCommand.self, rest).perform(makeStepper: makeStepper)
        case MirrorScrollCommand.configuration.commandName:
            return try parsed(MirrorScrollCommand.self, rest).perform(makeStepper: makeStepper)
        case MirrorMenuCommand.configuration.commandName:
            return try parsed(MirrorMenuCommand.self, rest).perform(makeStepper: makeStepper)
        case MirrorBurstCommand.configuration.commandName:
            return try parsed(MirrorBurstCommand.self, rest).perform(makeStepper: makeStepper)
        default:
            throw MCPError(message: "mirror was handed no action it knows (\(arguments.first ?? "none")) — this server and its mirror commands disagree", kind: .toolError)
        }
    }

    /// `session`'s six actions: `MCPToolInvocation` leads the vector with the action, spelled as the subcommand's own name, and the rest is that subcommand's command line — so each action answers what `simwalk session <action>` prints, through the same `perform`.
    ///
    /// `cancellation` reaches `start` alone, the one action that writes the session's progress file; a cancelled step has already been sent to the runner, and the session it steps in is not what was cancelled (`Docs/SIMWALK-PROGRESS.md` §3).
    static func sessionAnswer(
        _ arguments: [String],
        store: LiveSessionStore = .standard(),
        processes: any LiveSessionProcesses = LiveSessionSystemProcesses(),
        pause: @escaping (TimeInterval) -> Void = Thread.sleep(forTimeInterval:),
        now: @escaping () -> Date = { Date() },
        cancellation: Cancellation? = nil,
        shell: Shell = Shell(),
        runner: (() throws -> RunnerSource)? = nil,
        builds: RunnerBuilds = .standard(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        animationsLibrary: WalkCommand.AnimationsLibrary? = nil
    ) throws -> Answer {
        let rest = Array(arguments.dropFirst())
        switch arguments.first {
        case SessionStartCommand.configuration.commandName:
            return try parsed(SessionStartCommand.self, rest).perform(shell: shell, pause: pause, now: now, runner: runner, builds: builds, store: store, processes: processes, environment: environment, cancellation: cancellation, animationsLibrary: animationsLibrary)
        case SessionReadCommand.configuration.commandName:
            return try parsed(SessionReadCommand.self, rest).perform(store: store, processes: processes, pause: pause, now: now)
        case SessionStepCommand.configuration.commandName:
            return try parsed(SessionStepCommand.self, rest).perform(store: store, processes: processes, pause: pause, now: now)
        case SessionSaveCommand.configuration.commandName:
            return try parsed(SessionSaveCommand.self, rest).perform(store: store)
        case SessionEndCommand.configuration.commandName:
            return try parsed(SessionEndCommand.self, rest).perform(store: store, processes: processes, pause: pause, now: now)
        case SessionListCommand.configuration.commandName:
            _ = try parsed(SessionListCommand.self, rest)
            return SessionListCommand.answer(store: store, processes: processes, pause: pause, now: now)
        default:
            throw MCPError(message: "session was handed no action it knows (\(arguments.first ?? "none")) — this server and its session commands disagree", kind: .toolError)
        }
    }

    /// `inspect`'s own two commands: `MCPToolInvocation` leads the vector with `BundleScreenCommand`'s own name once a `step` was given, so this is the one place that name is read back rather than assumed — the two files agree on it the same way the CLI and the MCP face agree on `--settle`.
    ///
    /// **The length check is load-bearing, not the spelling.** A plain inspect is always the one-element vector `[bundle]` — `MCPToolInvocation` never builds another shape for it — so a bundle path that happens to be spelled `"screen"` still routes here rather than into `BundleScreenCommand` with its own path dropped as the sentinel: routing on the vector's shape, which the invocation guarantees, rather than on text a caller's argument could coincidentally supply.
    private static func inspectAnswer(_ arguments: [String]) throws -> Answer {
        guard arguments.count > 1, arguments.first == BundleScreenCommand.configuration.commandName else {
            return try parsed(BundleInspectCommand.self, arguments).answer()
        }
        return try parsed(BundleScreenCommand.self, Array(arguments.dropFirst())).answer()
    }

    /// Parses one command, restating a parser failure in the command's own words.
    ///
    /// ArgumentParser wraps a command's `validate()` refusal in its own error type, whose description is the parser's internals rather than the sentence the command wrote — and that sentence is the whole value of the refusal. `message(for:)` unwraps it, so `--settle 0` reaches an MCP caller saying what it says on a terminal.
    ///
    /// **The two failures this can throw are not the same kind.** A `validate()` refusal is the command's own refusal of a caller's argument — a bad `--settle`, caught here because `MCPToolInvocation` cannot see across commands — and is `.inputRefused` like any other. Anything else means `.parse(_:)` rejected a vector `MCPToolInvocation` had already built and checked — an unknown option, a missing value — which is this server and this command disagreeing about the argument shape, not a caller's mistake, and is `.toolError`.
    ///
    /// **Telling them apart needs `isCommandsOwnValidationFailure`, not a `catch` clause.** `ParsableCommand.parseAsRoot(_:)` (which `.parse(_:)` calls) invokes `validate()` on the freshly decoded command *itself*, before returning, and wraps a refusal in the identical internal `CommandError` a structural rejection uses — `MessageInfo` renders both the same way and even `exitCode(for:)` answers `.validationFailure` for both, so there is no public type or API to catch a `validate()` refusal specifically. Two stages of parsing (a `parseAsRoot` half we control, then `validate()` called separately) was the first design tried here and does not work, for the same reason: `parseAsRoot` already validates.
    private static func parsed<Command: ParsableCommand>(_ type: Command.Type, _ arguments: [String]) throws -> Command {
        do {
            return try type.parse(arguments)
        } catch {
            let kind: UsageFailureKind = isCommandsOwnValidationFailure(error) ? .inputRefused : .toolError
            throw MCPError(message: type.message(for: error), kind: kind)
        }
    }

    /// Whether `error` is ArgumentParser's own wrapper for a command's `validate()` throwing — read by reflection on the error's shape rather than by importing a type, because the wrapper (`CommandError`, carrying a `ParserError` whose `userValidationError` case is exactly this) is internal to the `ArgumentParser` module and neither is nameable from here.
    ///
    /// Failing to recognise the shape — a genuine parser rejection, or ArgumentParser renaming this case in some future version — answers `false` and routes to `.toolError`, the side this taxonomy already treats as safe to over-report: a `validate()` refusal wrongly called `.toolError` still counts as a real failure and is never hidden, where the reverse mistake would exclude one from the headline it should not have escaped.
    ///
    /// **The type name is checked before the shape, and both must match.** A shape alone is a lookalike's to borrow — any error carrying a `parserError` child whose case is labelled `userValidationError` — and reading one as a caller's refusal is the unsafe direction. Kept on `Mirror` rather than restructured through ArgumentParser's public API (every command's options moved into an `@OptionGroup`, parsed alone, `validate()` then called by hand): that is a rewrite of all four commands' declarations for a check that already fails safe.
    ///
    /// Internal rather than private so a test can hold the lookalike to it.
    static func isCommandsOwnValidationFailure(_ error: Error) -> Bool {
        guard String(reflecting: type(of: error)) == "ArgumentParser.CommandError",
              let parserError = Mirror(reflecting: error).children.first(where: { $0.label == "parserError" })?.value
        else {
            return false
        }
        return Mirror(reflecting: parserError).children.first?.label == "userValidationError"
    }
}

extension MCPToolRunner {
    /// What a walk touches on the machine, named so a test hands scratch ones: the shell, the runner it resolves, and where it records builds and leases.
    ///
    /// A session start is handed the first three.
    struct WalkSeams {
        var shell = Shell()
        var runner: (() throws -> RunnerSource)?
        var builds: RunnerBuilds = .standard()
        var leases: LeaseStore = .standard()
    }
}
