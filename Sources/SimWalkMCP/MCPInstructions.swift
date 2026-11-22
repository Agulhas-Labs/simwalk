//
// Copyright © Agulhas Labs
//

/// The `instructions` string of the `initialize` result.
///
/// A bounded client gets the full short guide. Claude Code gets only a pointer to the guide and the reference: its guide is a path-scoped rule file that never loads in a repo with no walkbooks, which is exactly where first use happens, and without a path the agent searched the whole disk for `Reference.md` (SimWalk#293). The pointer stays small because every session pays it.
struct MCPInstructions {
    /// The `instructions` for `mode`, naming `paths` where they are known.
    static func text(for mode: MCPClientMode, paths: MCPGuidePaths) -> String {
        switch mode {
        case .bounded: bounded(reference: paths.reference)
        case .blocking: pointer(paths: paths)
        }
    }

    private static func referenceLine(_ reference: String?) -> String {
        reference.map { "Every verb and walkbook key: \($0)" } ?? "Every verb and walkbook key: Docs/Reference.md at github.com/Agulhas-Labs/simwalk"
    }

    private static func pointer(paths: MCPGuidePaths) -> String {
        var lines = ["SimWalk looks at a running iOS app's screens: their text, layout at a text size or theme, and audits. Reach for it instead of screenshots or simctl by hand."]
        if let guide = paths.guide {
            lines.append("Before first use, read the guide: \(guide)")
        }
        lines.append(referenceLine(paths.reference))
        return lines.joined(separator: "\n")
    }

    private static func bounded(reference: String?) -> String {
        let fullGuide = reference.map { "Full guide: \($0)" } ?? "Full guide: Docs/Reference.md at github.com/Agulhas-Labs/simwalk."
        return """
        SimWalk drives a running iOS app through a walkbook (*.walkbook.json) and writes a capture bundle: a screenshot and accessibility tree per screen, and a manifest of what happened. Prefer it to tapping through the app by hand.
        - After an app change, call walk with dryRun: true first. It checks every screen's route still resolves, in seconds, and captures nothing. validate checks a walkbook can run as written.
        - A full walk takes minutes. Here a walk call answers within a time budget: with the result, or with a handle. Pass the handle to walk_status until the result arrives. Start no second walk meanwhile.
        - The first line is the verdict. ok passes; "qualified — ..." is an answer with each qualification named, not a failure; "refused — ..." is an error saying what would make it answerable.
        - Read the answer and the bundle's manifest before any screenshot. For one screen's text, call inspect with step.
        - Don't reboot or drive the simulator by hand. A walk settles the device itself when it needs to.
        \(fullGuide)
        """
    }
}
