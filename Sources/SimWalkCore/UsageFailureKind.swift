//
// Copyright © Agulhas Labs
//

/// Why a call failed, coarse enough to act on and to price `simwalk usage`'s headline rate by.
///
/// A refusal a caller engineered on purpose — a bad argument, a walkbook that is not there — says nothing about whether the tool works; a route that would not land, a runner that did not complete, a device a restore could not put back, Claude Code's own configuration refusing a registration, and this tool contradicting itself each point somewhere different. The seven are exhaustive over what a failure site in this codebase currently means; a site that fails for a reason none of them names is a gap in this enum, to be reported rather than forced into the nearest one.
public enum UsageFailureKind: String, Codable, Equatable, Sendable {
    /// The call refused what it was given, before or instead of doing any real work: a bad argument, a missing walkbook, an uninstalled bundle ID, an invalid settle, a refused output path.
    ///
    /// Excluded from `simwalk usage`'s headline failure rate: a caller deliberately testing a refusal path getting refused is the tool working, not the tool failing.
    case inputRefused = "input-refused"
    /// A route step could not reach the element its label named, badly enough to fail the whole call rather than qualify one screen of it.
    case routeUnreachable = "route-unreachable"
    /// The walk runner itself did not build or complete — `xcodebuild`, the runner's own snapshot or pairing with this binary, or a bundle it wrote that does not hold up when read back.
    case runnerFailed = "runner-failed"
    /// A device was left in a state a restore could not put back.
    case deviceLeftBad = "device-left-bad"
    /// `install-hook`/`uninstall-hook` could not register or unregister with Claude Code's own CLI — not a walkbook, a route, the runner or a device, but the caller's Claude Code configuration.
    case setupFailed = "setup-failed"
    /// This tool's own code failed or contradicted itself, outside the runner — nothing any caller typed.
    ///
    /// Two shapes today: the MCP face building an argument vector its own command rejects (a `validate()` refusal of a caller's own argument stays `inputRefused`; this is a parse failure after that argument has already been checked), and a verb whose own work past reading its argument — hashing a walkbook it has already loaded, summarising a bundle it has already read — fails for a reason no error type classifies.
    case toolError = "tool-error"
    /// iPhone Mirroring was not frontmost when the guard looked (exit 3): not a fault of the tool or of the caller's argument, and the one failure whose right response is to retry.
    case notFrontmost = "not-frontmost"
}

public extension UsageFailureKind {
    /// The kind a log line written before this field existed reports as, read off its own recorded error text — never by rewriting the line.
    ///
    /// Matched only on a phrase specific to exactly one kind's own sites. Several `CaptureBundleError` shapes (`"has no manifest"`, `"does not describe a walk that could have happened"`, `"states bundle format"`) are deliberately absent: `bundle inspect` reading a caller's own bundle and a walk reading back the bundle its own runner just wrote can print the identical sentence for two different reasons, and the text alone cannot tell them apart — which is exactly the case this report counts as `unclassified` rather than guesses at.
    ///
    /// **`"is not installed on"` is deliberately absent too, for an older reason than any of those.** `Simulator.installedAppPath` used to turn *any* non-zero `simctl get_app_container` exit into that sentence — a CoreSimulator error or another agent's device shutdown included — and only the fix that narrowed it to simctl's own "not installed" text made the phrase unambiguous going forward. A line already on disk from before that fix cannot be told apart from one written after it by its text alone, and the one thing this report must never do is read a line that could be `runner-failed` as `input-refused` — hiding a real failure is worse than over-counting a refusal (the rule this whole field exists to serve). Such a line counts as `unclassified` rather than risk the read going the unsafe way.
    ///
    /// **ArgumentParser's own sentences are absent for the same reason** — `Missing expected argument` and `Missing value for '--`. Only the MCP face can record one (on the command line a parse failure happens before `run()`, so nothing is timed or logged), and there it means the vector `MCPToolInvocation` built and checked was rejected by its own command: `tool-error`, which is how the live path classifies it. A walkbook named `-x.json`, or one named `--version`, and a negative `settle` passed as a separate token, all produced exactly that text from this server's own bugs. MCP servers started before a deploy go on writing kind-less lines with this build's text, so the inference would keep applying — and it would keep putting a real failure where the headline cannot see it.
    static func inferred(fromErrorText text: String) -> UsageFailureKind? {
        for (marker, kind) in textMarkers where text.contains(marker) {
            return kind
        }
        return nil
    }

    /// Substrings unique to one kind's own error text — **order matters**.
    ///
    /// `the walk did not complete:` embeds the runner's own output, which can itself be a quoted `WalkbookLoadError` describing the walkbook that failed inside the walk — so a line that legitimately means `runner-failed` can also contain an `input-refused` marker further in. Runner markers are checked first so the outer, real error wins over a phrase quoted inside it; within a group, a marker specific enough that a line matching one would not also match another needs no ordering against its own siblings.
    private static var textMarkers: [(String, UsageFailureKind)] {
        [
            // runner-failed — the runner's own build, walk, snapshot or pairing. Checked first: several of
            // these embed the runner's captured output, which can itself quote a lower-level error.
            ("the walk runner could not be built", .runnerFailed),
            ("the walk did not complete:", .runnerFailed),
            ("no walk runner is installed for this simwalk binary", .runnerFailed),
            ("the walk runner snapshot for commit", .runnerFailed),
            ("must be a SimWalkRunner.xcodeproj", .runnerFailed),
            ("cannot read this simwalk binary to tell which runner", .runnerFailed),
            ("is not a git checkout the runner can be snapshotted from", .runnerFailed),
            ("is not an app bundle — ", .runnerFailed),
            ("to identify the build being walked", .runnerFailed),
            ("no available simulators", .runnerFailed),
            ("the format is not what this build expects", .runnerFailed),

            // input-refused — a bad walkbook, a bad CLI/MCP argument, a bad bundle or device name.
            ("cannot read walkbook at", .inputRefused),
            ("is not a walkbook:", .inputRefused),
            ("is not executable — ", .inputRefused),
            ("no screen named", .inputRefused),
            ("no simulator named", .inputRefused),
            ("is not named as a capture bundle", .inputRefused),
            ("a walk writes a fresh bundle", .inputRefused),
            ("unknown tool '", .inputRefused),
            ("which was not given", .inputRefused),
            ("was given a blank '", .inputRefused),
            ("it takes a path", .inputRefused),
            ("it takes a non-empty string", .inputRefused),
            ("it takes a whole number of milliseconds", .inputRefused),
            ("it takes an array of screen ids", .inputRefused),
            ("every entry is a screen id", .inputRefused),
            ("takes a quiet period in milliseconds", .inputRefused),
            ("declares iPhone only (UIDeviceFamily", .inputRefused),
        ]
    }
}
