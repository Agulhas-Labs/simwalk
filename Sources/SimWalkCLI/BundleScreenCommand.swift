//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore

/// `simwalk bundle screen <path> <step>` — one screen's identifier and the text on screen, in accessibility order.
///
/// The question after a walk is almost always about one capture: which screen a step actually reached, or what one line of it says — and `bundle inspect` answers neither, because a manifest names screens and outcomes, not their content. Reading `ax-tree.json` by hand or opening `screen.png` are the two things this exists to make unnecessary for a text question (SimWalk#20); a shape question — a capsule versus a line — still needs the screenshot, and the answer says so.
struct BundleScreenCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screen",
        abstract: "Read one screen's text: its screen identifier and the text on screen, in accessibility order.",
        usage: "simwalk bundle screen <bundle> <step> [--state <state>] [--match <match>] [--all] [--tree] [--bars]"
    )

    @Argument(help: "Path to a capture bundle directory.")
    var bundle: String

    /// Every token the parser did not claim, of which exactly one is expected: the step — read through ``leftovers``, which tells a step from an option this command does not take and honours `--`.
    ///
    /// **An array only so that a dash-leading step reaches ``validate()``.** Declared as a single `String`, `-1` reads to ArgumentParser as an option it does not know, and the caller gets "Missing expected argument '<step>'" — a sentence about the parser, and a false one. Collected here, `-1` is refused in this command's own words and a screen id beginning with `-` is looked up like any other; the usage line above states the one-value shape the array hides.
    @Argument(parsing: .allUnrecognized, help: ArgumentHelp("The screen's 1-based position in the walk (as `bundle inspect` numbers it), or the screen's own id.", valueName: "step"))
    var step: [String] = []

    /// `.unconditional` so a value beginning with `-` is the option's value rather than a second option — `--state -x` as well as `--state=-x`.
    @Option(name: .long, parsing: .unconditional, help: "Which of the screen's captured states to read, by slug (for example 'light' or 'dark'). With none named, a screen holding several answers for the first and names the others.")
    var state: String?

    /// `.unconditional` for the reason `state` is: `--match -2` is a search for "-2", not `--match` given nothing.
    @Option(name: .long, parsing: .unconditional, help: "Only the text elements whose label or value contains this text (case-insensitive), on screen or off it; off-screen hits are listed after the on-screen ones, marked.")
    var match: String?

    /// Off-screen elements are counted by default, and at large type most of a page is below the fold, so a reader looking for one had no way to list them (SimWalk#101).
    ///
    /// The property is not called `all`, which Swift reads as the SIMD mask function.
    @Flag(name: .customLong("all"), help: "List the off-screen elements too, after the on-screen ones, each marked '(off screen)'.")
    var listsOffScreen = false

    /// Lists the nodes `--match` names with their identifier, frame, selected flag and ancestors, rather than the text (SimWalk#121).
    @Flag(name: .customLong("tree"), help: "List the nodes --match names (text, identifier or type) with identifier, frame, selected flag and ancestor chain, instead of the text.")
    var listsTree = false

    /// Lists every tab bar, toolbar and navigation bar with its frame; alone it implies the tree listing.
    @Flag(name: .long, help: "List the tab bars, toolbars and navigation bars with their frames; alone, or with --tree --match for the union.")
    var bars = false

    /// Refuses a step below 1 before opening anything, on the same reasoning `WalkCommand` refuses a `--settle` the runner would discard — and a missing step, a second one, or an option this command does not take, in this command's own words rather than the parser's.
    ///
    /// A step naming a screen id, or a position outside the walk's plan, is refused once the manifest is open, where the plan can be named.
    func validate() throws {
        let tokens = leftovers
        if let unknown = tokens.options.first {
            throw ValidationError("'\(unknown)' is not an option this command takes — it takes --state, --match, --all, --tree and --bars; a screen id beginning with '--' goes after a '--'")
        }
        guard let first = tokens.steps.first else {
            throw ValidationError("<step> is required — a screen's 1-based position in the walk, or its screen id")
        }
        guard tokens.steps.count == 1 else {
            if let option = shortOptions.first {
                throw ValidationError("'\(option)' is not an option this command takes — it takes --state, --match, --all, --tree and --bars; a screen id beginning with '-' goes after a '--'")
            }
            let rest = tokens.steps.dropFirst().map { "'\($0)'" }.joined(separator: ", ")
            throw ValidationError("<step> names one screen; '\(first)' was followed by \(rest), which is neither a second step nor an option this command takes")
        }
        if listsTree, !bars, match == nil {
            throw ValidationError("--tree lists the nodes --match names (text, identifier or type); --bars lists the bars alone")
        }
        if let position = Int(first), position < 1 {
            throw ValidationError("<step> is a screen's 1-based position in the walk, or its screen id; \(position) is not one")
        }
    }

    /// The parser's leftovers read as a person typing them means them.
    ///
    /// Before a `--`, a token beginning with `--` is an option this command does not take — never a step, which is how `--bogus foo 1` came to name `--bogus` as the step; after the first `--`, every token is a step, as POSIX has it, so `-- -1` is the step `-1` and `-- --odd` a screen id. A token beginning with a single `-` is a step on either side: `-1` has to reach the below-1 refusal, and a lone `-legacy` is a screen id — ``shortOptions`` says what one means beside another step.
    private var leftovers: (options: [String], steps: [String]) {
        let terminator = step.firstIndex(of: "--") ?? step.endIndex
        let before = step[..<terminator]
        let after = terminator < step.endIndex ? Array(step[(terminator + 1)...]) : []
        return (before.filter { $0.hasPrefix("--") }, before.filter { !$0.hasPrefix("--") } + after)
    }

    /// The tokens before any `--` that begin with a single `-` and are not numbers: standing beside another step, as in `-s light 1`, such a token is an option this command does not take, not the first of three steps.
    private var shortOptions: [String] {
        step.prefix { $0 != "--" }.filter { $0.hasPrefix("-") && !$0.hasPrefix("--") && Int($0) == nil }
    }

    func run() throws {
        try run(log: .standard(), emit: StandardStreams.emit, emitError: StandardStreams.emitError, isStdoutPiped: StandardStreams.isStdoutPiped)
    }

    /// The same run with its three effects injectable, for the reason `TimedCall` takes them: the contract this command holds is an exit code, and an exit code is only checkable against the command itself.
    func run(log: UsageLog, emit: (String) -> Void, emitError: (String) -> Void, isStdoutPiped: () -> Bool = { false }) throws {
        try TimedCall.run(tool: BundleScreenQuery.logName, target: bundle, log: log, emit: emit, emitError: emitError, defaultFailureKind: .toolError, isStdoutPiped: isStdoutPiped) {
            try answer()
        }
    }

    /// The answer, without the printing — what the MCP face serves, so one verb cannot come to answer differently depending on which face asked.
    func answer() throws -> Answer {
        let opened = try CaptureBundle.read(at: URL(fileURLWithPath: bundle))
        return try BundleScreenQuery(opened).answer(step: leftovers.steps.first ?? "", state: state, match: match, all: listsOffScreen, tree: listsTree, bars: bars)
    }
}
