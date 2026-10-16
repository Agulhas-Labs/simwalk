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
        return tree.flattened.contains { $0.type == "Keyboard" && $0.flattened.contains(node) }
    }
}
