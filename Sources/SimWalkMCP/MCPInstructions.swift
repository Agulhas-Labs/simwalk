//
// Copyright © Agulhas Labs
//

/// The `instructions` string of the `initialize` result, sent to every client but Claude Code (which has the full guide as a rule file, so its idle cost stays zero).
struct MCPInstructions {
    static var text: String {
        """
        SimWalk drives a running iOS app through a walkbook (*.walkbook.json) and writes a capture bundle: a screenshot and accessibility tree per screen, and a manifest of what happened. Prefer it to tapping through the app by hand.
        - After an app change, call walk with dryRun: true first. It checks every screen's route still resolves, in seconds, and captures nothing. validate checks a walkbook can run as written.
        - A full walk takes minutes. Here a walk call answers within a time budget: with the result, or with a handle. Pass the handle to walk_status until the result arrives. Start no second walk meanwhile.
        - The first line is the verdict. ok passes; "qualified — ..." is an answer with each qualification named, not a failure; "refused — ..." is an error saying what would make it answerable.
        - Read the answer and the bundle's manifest before any screenshot. For one screen's text, call inspect with step.
        - Don't reboot or drive the simulator by hand. A walk settles the device itself when it needs to.
        Full guide: Docs/Reference.md at github.com/Agulhas-Labs/simwalk.
        """
    }
}
