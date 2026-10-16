//
// Copyright © Agulhas Labs
//

import Foundation

/// Whether a screen's captures show the menu its walkbook `expectMenu`ed, judged by the `Button` labels in each tree (SimWalk#111).
///
/// **Why a menu needs its own check.** A route that ends by opening a SwiftUI system `Menu` cannot be verified by `expect`: the open menu hides the screen's identifier and carries none of its own, so `expect` refused a menu that was open and correct and the author had to delete it. What a real capture of an open menu does hold is its items, as `Button` nodes in a `CollectionView` (there is no `Menu` or `MenuItem` node type), each labelled with its title. So the check is against those labels.
///
/// **An ordered subsequence, matched exactly.** The listed labels must appear among the tree's `Button` labels in tree order — or in reverse, since a menu opening upwards lists its items bottom-up — other buttons allowed between them (a menu's checkmarked item is still a `Button`, and a screen's own buttons may sit behind it). Like `expect` this is a check and not a route step: a label is compared whole (`node.label == label`), never by a leading component and never with `{n}` — the menu's items are what the author is pinning.
///
/// **Every capture is checked**, for the reason `ExpectedScreenCheck` checks every one: a menu that opens under `light` and not under `dark` must not pass by averaging.
///
/// **`expect` is a separate check.** Both keys may be stated and each is judged on its own; an open menu hides the screen's identifier, so `expect` beside `expectMenu` normally fails.
public struct ExpectedMenuCheck {
    /// The most `Button` labels a mismatch's reason lists before it counts the rest.
    private static let listedLabelLimit = 8

    /// The outcome a screen must be recorded under given the trees its captures actually produced, or `intended` when the screen names no menu or every tree shows it.
    ///
    /// `found` is each mismatched capture's first screen-level identifier exactly as `ExpectedScreenCheck` computes it (`nil` for none), distinct and in order — so `expected 'menu: …', found [menus-screen]` reads as "the menu did not open". The `reason` names the first listed label not found in order and the `Button` labels the first mismatched capture holds.
    ///
    /// **Composition mirrors `ExpectedScreenCheck.outcome`** and is exhaustive for the same reason. An `intended` that is already an `.unexpectedScreen` (the `expect` check mismatched first) keeps its expected and found and gains the menu clause in its reason.
    public static func outcome(for trees: [AXNode], expectMenu: [String]?, instead intended: ScreenOutcome) -> ScreenOutcome {
        guard let expectMenu, !expectMenu.isEmpty else { return intended }
        let misses = trees.compactMap { tree in missing(expectMenu, in: tree).map { (tree: tree, label: $0) } }
        guard let first = misses.first else { return intended }
        let clause = reason(missing: first.label, buttons: buttonLabels(in: first.tree))
        let expected = "menu: \(expectMenu.joined(separator: ", "))"
        let found = distinct(misses.map { ScreenIdentifierRule.screenIdentifier(of: $0.tree) })
        return switch intended {
        case .captured:
            .unexpectedScreen(expected: expected, found: found, reason: clause)
        case let .captureFailed(failure):
            .unexpectedScreen(expected: expected, found: found, reason: "\(clause). The screen also failed mid-capture: \(failure)")
        case let .stateNotApplied(existing):
            .unexpectedScreen(expected: expected, found: found, reason: "\(clause). \(existing)")
        case let .unexpectedScreen(priorExpected, priorFound, existing):
            .unexpectedScreen(expected: priorExpected, found: priorFound, reason: existing.map { $0.hasSuffix(clause) ? $0 : "\($0). \(clause)" } ?? clause)
        case .unreachable, .buildMismatch:
            // Verdicts that file nothing: a tree handed in beside one is not evidence this screen holds.
            intended
        }
    }

    /// The first of `labels` that the tree's `Button` labels do not hold in order read top-down, or `nil` when they hold them all in order read either way up.
    ///
    /// **Either way up**, because iOS lists a menu's items nearest the control that opened it first: a menu opening upwards from a control low on the screen reads bottom-up, and the fixture's `Kind` menu came back `Strength, Walking, Endurance` on the first live walk of this check. The author's order is still held, in whichever direction the menu opened; a shuffle is still a mismatch.
    private static func missing(_ labels: [String], in tree: AXNode) -> String? {
        let buttons = buttonLabels(in: tree)
        guard let missed = firstMissing(labels, among: buttons) else { return nil }
        return firstMissing(labels, among: buttons.reversed()) == nil ? nil : missed
    }

    /// The first of `labels` that `buttons` do not hold in order, or `nil` when they all do.
    private static func firstMissing(_ labels: [String], among buttons: [String]) -> String? {
        var remaining = labels[...]
        for button in buttons {
            if remaining.first == button {
                remaining.removeFirst()
            }
            if remaining.isEmpty {
                return nil
            }
        }
        return remaining.first
    }

    private static func buttonLabels(in tree: AXNode) -> [String] {
        tree.flattened.compactMap { $0.type == "Button" ? $0.label : nil }
    }

    private static func reason(missing label: String, buttons: [String]) -> String {
        let listed = buttons.prefix(listedLabelLimit).map { "'\($0)'" }.joined(separator: ", ")
        let held = if buttons.isEmpty {
            "it holds no Button labels"
        } else if buttons.count > listedLabelLimit {
            "its Buttons are \(listed) and \(buttons.count - listedLabelLimit) more"
        } else {
            "its Buttons are \(listed)"
        }
        return "Menu label '\(label)' was not found among the Buttons in order; \(held)"
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
