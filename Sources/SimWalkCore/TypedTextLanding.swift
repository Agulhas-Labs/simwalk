//
// Copyright © Agulhas Labs
//

import Foundation

/// Whether a `type` step's text actually reached the field, judged from the field's own value either side of the typing.
///
/// **A field's `value` is its placeholder when it is empty**, which is what makes the obvious check wrong. XCUITest reports a real app's empty search field by its placeholder, a list of the things it searches for, so a step typing one of those words into a field it never focused reads back a value containing it and reports the step as having landed — over a screen captured empty. That is the silent-discard shape the whole walkbook validation exists to refuse, reintroduced by the check meant to catch it.
///
/// **So the evidence is the change, not the contents.** A field that took the text is a field whose value is not what it was, and which now carries what was typed. Neither half is sufficient alone: unchanged means nothing happened however promising the placeholder looks, and a value that merely contains the text may be the placeholder that always did.
public struct TypedTextLanding {
    /// Whether the field is now carrying what was typed into it.
    ///
    /// `redactedValue` is for a secure field, which reports bullets rather than its contents: there is nothing to compare the text against, so the containment half is dropped and the change half is not. Passing such a field unconditionally was the first version and is a check that cannot fail, which is the same as no check — this one still refuses a secure field that did not change at all.
    ///
    /// The conservative direction is deliberate. A field that already held the text and was typed into again may produce a value equal to what it was, and this reports that as not landed — a walk refused over something that may have worked, which is the trade every honest-contract decision here makes: a false refusal is arguable, a false capture is not.
    public static func landed(text: String, before: String?, after: String?, redactedValue: Bool = false) -> Bool {
        guard after != before else { return false }
        guard !redactedValue else { return true }
        return after?.contains(text) == true
    }

    /// How many delete keystrokes clear a field reading `value`: one per character it reads, whether or not the value is also its placeholder (SimWalk#198).
    ///
    /// **A real value can equal the placeholder** (a number field holding `0` over the placeholder `0`), so the placeholder is not a reason to send none; the extra keystrokes an empty field reading its placeholder receives delete nothing.
    public static func deleteKeystrokes(value: String?) -> Int {
        value?.count ?? 0
    }

    /// What a field still holds that a delete should have removed: nothing when it reads empty or as its placeholder (SimWalk#198).
    ///
    /// **An empty field reports its placeholder as its value**, so a read equal to the placeholder is taken as empty here, where deleting has already been tried in full and a retry could not tell the two apart.
    public static func remainingText(value: String?, placeholder: String?) -> String {
        guard let value, !value.isEmpty, value != placeholder else { return "" }
        return value
    }

    /// How many times a `replace` taps the trailing edge and deletes before it gives up on text that keeps coming off (SimWalk#214).
    ///
    /// A field whose text runs past its width puts the cursor at the visible end, so each pass removes about a field's width; six passes clear roughly six widths, and a bound keeps a field that regrows its text from looping.
    public static let trailingEdgePassLimit = 6

    /// Whether another trailing-edge delete pass is worth making after pass number `pass` (1-based), given what the field held either side of it (SimWalk#214).
    ///
    /// **Progress is the licence**: a pass that changed the field's text moved the cursor's reach on, so another may reach more (a masked field swaps characters for placeholders and keeps its length, SimWalk#219); a pass that changed nothing will change nothing again, and what is left sits on the other side of the cursor (the leading-edge pass). Nothing remaining means nothing to retry, and the bound keeps a field that regrows its text from looping.
    public static func shouldRetryTrailingEdge(before: String, after: String, pass: Int) -> Bool {
        !after.isEmpty && after != before && pass < trailingEdgePassLimit
    }

    /// Why a `replace` that deleted its field's text found some left, or `nil` when none was (SimWalk#198).
    ///
    /// Named for what remained, so the agent sees whether the cursor or the field is the problem.
    public static func stillHeldRefusal(label: String, remaining: String) -> String? {
        remaining.isEmpty ? nil : "'\(label)' still held '\(remaining)' after its text was deleted"
    }

    /// Why a `replace` did not leave the field holding `text`, or `nil` when it did (SimWalk#198).
    ///
    /// **Verified, not trusted**: the read-back is compared with the text, and the reason names the value found so the agent sees what the field holds. An empty `text` is satisfied by an empty field, which reads back empty, absent or as its placeholder; a non-empty `text` that equals the placeholder lands when the field reads it. A field whose keystrokes did not land would read the placeholder too, so that one case trusts the typing: the alternative refuses every replacement that happens to equal the placeholder.
    public static func replaceRefusal(label: String, text: String, after: String?, placeholder: String?) -> String? {
        if text.isEmpty {
            guard let after, !after.isEmpty, after != placeholder else { return nil }
        } else if after == text {
            return nil
        }
        return "'\(label)' holds '\(remainingText(value: after, placeholder: placeholder))' after replacing its text"
    }

    /// The reason a `replace` stops when a tap left its field without keyboard focus, before any keystroke.
    public static func unfocusedReplaceRefusal(label: String) -> String {
        "'\(label)' did not take keyboard focus when tapped, so its text was not replaced"
    }

    /// Why a `replace` into a secure field is refused: its value reads back as bullets, so the replacement cannot be verified (SimWalk#198).
    public static func secureReplaceRefusal(label: String) -> String {
        "'\(label)' is a secure field, whose value cannot be read back, so replace is refused"
    }

    /// Whether a tap on a keyboard key reached the field, judged from the focused field's own value either side of the tap (SimWalk#94).
    ///
    /// **A keystroke changes a value, and a screen's identity is deliberately blind to values** (`ScreenIdentity`), so a digit typed on a number pad leaves the screen "unchanged" however faithfully it landed. The evidence for a key is the field that has keyboard focus: a value that is not what it was. A delete key shrinking it counts, and so does a secure field's bullets changing; nothing is compared against the key's label, because a key's label is not what the field carries (a shift key types nothing, and a delete key types `Delete`).
    ///
    /// **A value that disappeared is not evidence.** `after` absent or unreadable is the focus query briefly matching nothing while the field re-renders, so it is reported as not landed; a Done that dismisses the keyboard is landed by the screen-identity half instead. `before` no field with an `after` is a field that took focus and its first character.
    ///
    /// **An unreadable `before` is no evidence either** (SimWalk#96). A read that failed says nothing about the field, so treating it as "no field" made every later value look like a first character and a tap that typed nothing landed. Neither side holding a field is a tap that found nothing to type into, and this reports it as not landed rather than guessing.
    public static func keyPressed(before: FocusedFieldValue, after: FocusedFieldValue) -> Bool {
        guard case let .value(now) = after else { return false }
        return switch before {
        case .unreadable: false
        case .none: true
        case let .value(was): now != was
        }
    }

    /// Whether a tapped key landed: the screen left, or the focused field's value is no longer what it was.
    ///
    /// The judgement `tap` makes of a key, in the core so a test can reach it (SimWalk#96): the screen half is the common one for a Done or a Return that moves on, the value half for a digit that leaves the screen as it was. `after` is read only when the screen has not left, as the live focus query is a read the runner pays for on every poll.
    public static func keyLanded(screenLeft: Bool, before: FocusedFieldValue, after: @autoclosure () -> FocusedFieldValue) -> Bool {
        screenLeft || keyPressed(before: before, after: after())
    }

    /// Whether `node`, a control the tap chose in `tree`, is a keyboard key and so judged by `keyLanded` rather than by the plain tap rule.
    ///
    /// **A Return key is often a `Button`** (SimWalk#96): XCUITest types the letters and digits as `Key` but exposes Return, Done and Search as buttons inside the keyboard, and those fell through to the plain rule, which has no notion of a focused field. So a `Button` with a `Keyboard` above it is a key; one anywhere else keeps the plain rule.
    public static func isKey(_ node: AXNode, in tree: AXNode) -> Bool {
        if node.type == "Key" {
            return true
        }
        guard node.type == "Button" else { return false }
        return tree.flattened.contains { ScreenIdentifier.isKeyboard($0) && $0.flattened.contains(node) }
    }
}
