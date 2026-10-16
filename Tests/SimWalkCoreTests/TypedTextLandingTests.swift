//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// The post-condition a `type` step reports itself by, and the placeholder trap that makes the obvious version of it wrong.
struct TypedTextLandingTests {
    /// The specimen: an app's search field reports `Search boats, crew, harbours…` while empty, so a containment check alone reports a step that never typed anything as having landed.
    @Test
    func aplaceholderContainingTheTextIsNotAFieldThatTookIt() {
        #expect(!TypedTextLanding.landed(
            text: "harbours",
            before: "Search boats, crew, harbours…",
            after: "Search boats, crew, harbours…"
        ))
    }

    /// The ordinary success: the placeholder gives way to what was typed.
    @Test
    func afieldWhoseValueBecameTheTextHasTakenIt() {
        #expect(TypedTextLanding.landed(
            text: "mean",
            before: "Search boats, crew, harbours…",
            after: "mean"
        ))
    }

    /// Changing is not enough on its own: a field that lost its placeholder on focus and took no keystrokes has changed and holds nothing.
    @Test
    func afieldThatChangedWithoutTakingTheTextHasNotTakenIt() {
        #expect(!TypedTextLanding.landed(text: "mean", before: "Search boats, crew, harbours…", after: ""))
    }

    /// A field that reports no value at all, before and after, has given no evidence of anything.
    @Test
    func afieldThatReportsNoValueEitherSideHasNotTakenIt() {
        #expect(!TypedTextLanding.landed(text: "mean", before: nil, after: nil))
    }

    /// A secure field reports bullets rather than its contents, so the containment half is dropped — but not the change half, or the check could not fail at all.
    @Test
    func asecureFieldIsJudgedByChangeAloneAndStillHasToChange() {
        #expect(TypedTextLanding.landed(text: "hunter2", before: "", after: "••••••", redactedValue: true))
        #expect(!TypedTextLanding.landed(text: "hunter2", before: "", after: "", redactedValue: true))
    }

    /// A digit appended, a delete key shrinking the value, and a secure field's bullets changing are all keys that landed.
    @Test
    func akeyPressIsLandedWhenTheFocusedFieldsValueChanged() {
        #expect(TypedTextLanding.keyPressed(before: .value("500"), after: .value("5000")))
        #expect(TypedTextLanding.keyPressed(before: .value("5000"), after: .value("500")))
        #expect(TypedTextLanding.keyPressed(before: .value("••"), after: .value("•••")))
    }

    /// A value that is what it was means the key typed nothing, however it was labelled.
    @Test
    func akeyPressIsNotLandedWhenTheValueIsUnchanged() {
        #expect(!TypedTextLanding.keyPressed(before: .value("500"), after: .value("500")))
    }

    /// With no field holding keyboard focus there is no value to have changed.
    @Test
    func akeyPressWithNoFocusedFieldIsNotLandedByValue() {
        #expect(!TypedTextLanding.keyPressed(before: .none, after: .none))
    }

    /// A value that vanished is the focus query matching nothing mid-render, not a keystroke.
    @Test
    func akeyPressIsNotLandedWhenTheValueDisappears() {
        #expect(!TypedTextLanding.keyPressed(before: .value("5"), after: .none))
        #expect(!TypedTextLanding.keyPressed(before: .value("5"), after: .unreadable))
    }

    /// A field that took focus and its first character goes from no field to a value.
    @Test
    func akeyPressIsLandedWhenAValueAppears() {
        #expect(TypedTextLanding.keyPressed(before: .none, after: .value("5")))
    }

    /// **A failed before-read is not a missing field** (SimWalk#96): read as "no field", the value that followed looked like a first character and a tap that typed nothing landed.
    @Test
    func anUnreadableBeforeIsNoEvidenceOfAKeystroke() {
        #expect(!TypedTextLanding.keyPressed(before: .unreadable, after: .value("500")))
    }

    /// The screen leaving lands a key whatever the field did, and the field is not even read then.
    @Test
    func aKeyLandsWhenTheScreenLeftOrTheValueChanged() {
        var fieldReads = 0
        func field() -> FocusedFieldValue {
            fieldReads += 1
            return .none
        }
        let left = TypedTextLanding.keyLanded(screenLeft: true, before: .none, after: field())

        #expect(left)
        #expect(fieldReads == 0)
        #expect(TypedTextLanding.keyLanded(screenLeft: false, before: .value("5"), after: .value("55")))
        #expect(!TypedTextLanding.keyLanded(screenLeft: false, before: .value("5"), after: .value("5")))
    }

    /// **A Return exposed as a Button inside the keyboard is a key** (SimWalk#96); a Button outside it keeps the plain tap rule.
    @Test
    func aButtonInsideTheKeyboardIsAKeyAndOneOutsideIsNot() {
        let frame = AXNode.Frame(x: 0, y: 0, width: 10, height: 10)
        let digit = AXNode(type: "Key", frame: frame, label: "5")
        let returnKey = AXNode(type: "Button", frame: frame, label: "Return")
        let save = AXNode(type: "Button", frame: frame, label: "Save")
        let tree = AXNode(type: "Application", frame: frame, children: [
            save,
            AXNode(type: "Keyboard", frame: frame, children: [digit, returnKey]),
        ])

        #expect(TypedTextLanding.isKey(digit, in: tree))
        #expect(TypedTextLanding.isKey(returnKey, in: tree))
        #expect(!TypedTextLanding.isKey(save, in: tree))
    }
}
