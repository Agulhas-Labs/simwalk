//
// Copyright © Agulhas Labs
//

import Foundation

/// Whether a screen's captures are of the screen its walkbook `expect`ed, judged by whether each one's tree is known by the identifier `expect` names — any of its screen-level identifiers (outermost or nested, SimWalk#103), never anything in the tab bar, toolbar or navigation bar, the bar's own title included.
///
/// **The evidence that would make "this screen was captured" false.** A route can complete, settle, and hold real content, and still not be the screen a walkbook believes it reached — the README's standing caveat that a route leaving the app records the wrong screenshot under a passing outcome, narrowed to the half of that hole a manifest can actually check: a wrong screen inside the same app, named by the accessibility identifier the app sets on it. `ScreenIdentity` already catches a step that never left the screen it was taken on; this catches the step one level up, where it *did* leave and simply arrived somewhere else.
///
/// **The match is against the screen's content, not the app root and not the app's frame.** `AXTreeCapture.tree(of:)` returns `app.snapshot()`, whose root is always the `Application` node — it never carries an identifier. A real screen's own identifier sits wherever the app set one, which on the captures this was checked against is a `ScrollView` seventeen levels below the root, so the whole tree is searched rather than a fixed depth; a pushed screen's parent does not stay in the tree once it is captured. What is *not* searched is chrome (`ScreenIdentifierRule`): the tab bar's symbol names, `BackButton`, `Toolbar` and SwiftUI's mangled hosting class sit on every screen, and an `expect` matching one of them would pass everywhere.
///
/// **Every capture is checked, not just one.** A screen's states are separate launches of the same route (Brief §7.4), so its identifier is a structural fact about the screen rather than about its appearance — nothing here should make it vary by theme, Dynamic Type or locale. Checking every capture rather than the first is what catches a route that lands on the right screen under `light` and the wrong one under `dark`, which a single-state check would file as a pass. That includes a screen that failed part-way: the captures it did take are filed, so they are held to `expect` like any other.
///
/// **A capture carrying no screen identifier is a mismatch, not a pass.** `expect` is opt-in exactly where an app has adopted the convention of setting one; a screen that asked for a check and got nothing back has not been verified, and passing it silently would be the same discard this file exists to end everywhere else in the walkbook.
///
/// **A navigation-bar title never satisfies it, and a mismatch says so when that is what `expect` named.** A screen whose content carries no identifier is known to a reader only by its title (`Heart`), and copying that out of a mismatch into `expect` makes a check that passes under `light`, flips under a `loc_fr_fr` state, and passes on any other screen titled the same. `validate` never sees a capture, so it cannot know a value is a title; the walk can, so the hint leads the mismatch's `reason` — naming the content's real identifier when it carries one (the case a fixed `expect` should be corrected to), or today's advice to set one when it carries none.
///
/// **Exact identifier match, never a leading component.** `RouteStep`'s label matching tolerates a composed label's live trailing count because SwiftUI writes that count for the author; a screen identifier is a value the app sets on purpose for exactly this kind of check, so a partial match would forgive the one thing `expect` exists to pin.
public struct ExpectedScreenCheck {
    /// The outcome a screen must be recorded under given the trees its captures actually produced, or `intended` when the screen names no expectation or every tree carries `expect`.
    ///
    /// `found` names each mismatched capture's first (outermost) screen identifier (`ScreenIdentifierRule.screenIdentifier(of:)`) — `nil` for a capture carrying none. So it never contains `expect` and is never empty: a mismatched tree carries no screen-level identifier equal to `expect`, so its first is not `expect` either, and there is at least one mismatched tree.
    ///
    /// **A mismatch keeps what `intended` already said.** A screen that failed mid-capture *and* filed a capture of the wrong screen has two things wrong with it, and recording only one would un-diagnose the other: the failure rides in `unexpectedScreen`'s `reason`, the same place a state refusal does (`StateApplicationCheck.refusedOutcome`). Exhaustive, so an outcome added later has to decide here what a mismatch does to it.
    public static func outcome(for trees: [AXNode], expect: String?, instead intended: ScreenOutcome) -> ScreenOutcome {
        guard let expect else { return intended }
        let mismatched = trees.filter { !ScreenIdentifierRule.carries(expect, in: $0) }
        guard !mismatched.isEmpty else { return intended }
        let found = distinct(mismatched.map(ScreenIdentifierRule.screenIdentifier(of:)))
        // The mismatch is exactly `expect` naming this screen's title: name the content's real identifier
        // when it carries one — that is what a corrected `expect` should say — rather than advising an
        // author to add one that is already there.
        let titleHint = mismatched.lazy.compactMap { tree -> String? in
            guard ScreenIdentifierRule.navigationBarTitle(of: tree) == expect else { return nil }
            if let identifier = ScreenIdentifierRule.screenIdentifier(of: tree) {
                return "'\(expect)' is this screen's navigation-bar title, which is localised and never counts; its stable identifier is '\(identifier)'"
            }
            return "'\(expect)' is this screen's navigation-bar title; titles are localised and never count; set an accessibilityIdentifier on the content"
        }.first
        return switch intended {
        case .captured:
            .unexpectedScreen(expected: expect, found: found, reason: titleHint)
        case let .captureFailed(failure):
            .unexpectedScreen(expected: expect, found: found, reason: joined(titleHint, "The screen also failed mid-capture: \(failure)"))
        case let .stateNotApplied(reason):
            .unexpectedScreen(expected: expect, found: found, reason: joined(titleHint, reason))
        case let .unexpectedScreen(_, _, reason):
            .unexpectedScreen(expected: expect, found: found, reason: joined(titleHint, reason))
        case .unreachable, .buildMismatch:
            // Verdicts that file nothing: a tree handed in beside one is not evidence this screen holds,
            // so there is nothing for a mismatch to be about.
            intended
        }
    }

    /// The hint about the mismatch itself first, then whatever else was already wrong — each once, so checking an outcome this already produced adds nothing — or `nil` when there is neither.
    private static func joined(_ hint: String?, _ existing: String?) -> String? {
        guard let hint else { return existing }
        guard let existing else { return hint }
        return existing.hasPrefix(hint) ? existing : "\(hint). \(existing)"
    }

    /// The values in the order they were found, each kept once.
    private static func distinct(_ values: [String?]) -> [String?] {
        var seen: [String?] = []
        for value in values where !seen.contains(value) {
            seen.append(value)
        }
        return seen
    }
}
