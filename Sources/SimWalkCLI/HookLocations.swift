//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimWalkDriver
import SimWalkMCP

/// Every place a registration writes, in one value — the three Claude Code reads, and the walk runner's snapshot.
///
/// A parameter rather than four calls to `standard()` inside the commands, because an installer whose destinations are hard-coded is one that can only be checked by running it against the machine it is being written on — and this one writes into somebody else's configuration directory. Handed a scratch directory it does the same work with nothing at stake, which is the only way "the uninstall reverses exactly what the install wrote" is a claim anything can hold.
struct HookLocations {
    /// Claude Code's settings file, where the `PreToolUse` hook goes (SimWalk#14), and the status line when sift is not here to carry it.
    let settings: URL

    /// Claude Code's own `.claude.json`, where `claude mcp add --scope user` records the server and where the install reads it back to confirm.
    let config: URL

    /// The user rule the agent guide is installed as.
    let rule: URL

    /// sift's segment directory, or `nil` when sift is not on this machine to carry a segment.
    let segments: StatuslineSegments?

    /// The render-time switch, so an install that leaves the line hidden says so.
    let visibility: StatuslineVisibility

    /// Where the walk runner is snapshotted and paired with the binary being installed (SimWalk#16).
    let runner: RunnerStore

    /// Where walks build the runner — pruned beside the store once the new runner is paired (SimWalk#22).
    let runnerBuilds: RunnerBuilds

    /// The installed binary, whose runner the prune keeps whichever binary is installing (SimWalk#22).
    let installedBinary: URL

    /// The machine's own locations, with the two a caller may override.
    static func standard(settings: String?, rule: String?) -> HookLocations {
        HookLocations(
            settings: settings.map { URL(fileURLWithPath: $0) } ?? SimWalkPaths.claudeSettings,
            config: AgentPaths.claudeConfig(environment: ProcessInfo.processInfo.environment),
            rule: rule.map { URL(fileURLWithPath: $0) } ?? SimWalkPaths.claudeRule,
            segments: StatuslineSegments.isAvailable ? .standard() : nil,
            visibility: .standard(),
            runner: .standard(),
            runnerBuilds: .standard(),
            installedBinary: ExecutablePath.installed()
        )
    }
}
