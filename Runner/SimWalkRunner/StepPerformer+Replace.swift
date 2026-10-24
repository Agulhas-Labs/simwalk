//
// Copyright © Agulhas Labs
//

import SimWalkCore
import XCTest

/// A text-entry element a `type` step resolved and bound, and the target it was bound to.
struct TextEntry {
    let element: XCUIElement
    let target: RouteTarget.Candidate
}

extension TextEntry {
    /// A `type` step that could not reach its field, carrying the result the step reports.
    ///
    /// Thrown from ``StepPerformer/bindTextEntry(_:)`` so `type` and its `replace` form share the resolving without either copying it.
    struct Refusal: Error {
        let result: StepPerformer.StepResult
    }
}

extension StepPerformer {
    /// Resolves `label` among text-entry elements only and binds it, or throws the refusal the step reports.
    ///
    /// The first node in tree order carrying the label is routinely the container a search field is drawn inside — and `typeText` on a container is an *XCTest failure*, which fails the whole walk rather than returning something this loop could report as a step that did not land.
    func bindTextEntry(_ label: String) throws -> TextEntry {
        let choice = try TargetResolution.resolve(label, reaching: .textEntry, in: app, quiet: quiet, budget: budget)
        guard case .chosen = choice else {
            throw TextEntry.Refusal(result: .blocked(reason: choice == .none ? nil : choice.reason(for: label)))
        }
        let binding = try TargetResolution.bind(choice, labelled: label, in: app, quiet: quiet, budget: budget) {
            TargetResolution.textEntry(for: $0, in: app)
        }
        guard case let .element(element, target, _) = binding else {
            throw TextEntry.Refusal(result: .blocked(reason: binding.refusal(doing: "typed into")))
        }
        return TextEntry(element: element, target: target)
    }

    /// A `type` with `"replace": true`: deletes what the field holds, types `text`, and lands only if the field then reads back as `text` (SimWalk#198).
    ///
    /// **The cursor is put at the end of the text, then one delete keystroke goes per character read**, placeholder or not (extra deletes in an empty field do nothing). A tap at the field's centre would leave the cursor mid-text, and backspaces delete only what lies before it, so the tap is at the trailing edge, or below a multi-line field's text. A field whose text runs past its width puts the cursor at the visible end, so the trailing-edge pass repeats while each pass changes the field's text, up to `TypedTextLanding.trailingEdgePassLimit` (SimWalk#214). Text that remains sits before the cursor in a right-to-left layout, so the leading edge is tried once after that; a left-to-right field whose text runs past its width can still hold text after that, and a field still holding text is refused rather than typed into. A tap that leaves the field without keyboard focus is refused too, before any keystroke. Every read of the field's value waits for it to hold still (`settledValue(of:)`), so an app that rewrites what was typed is refused with one stable reason. **Verified, not trusted**: the judgement is `TypedTextLanding.replaceRefusal`, in the core where a test reaches it. A secure field is refused before it is touched, because its value reads back as bullets and a replacement could not be checked.
    func replaceText(in label: String, with text: String) throws -> StepResult {
        let field: TextEntry
        do {
            field = try bindTextEntry(label)
        } catch let refusal as TextEntry.Refusal {
            return refusal.result
        }
        let element = field.element
        if element.elementType == .secureTextField {
            return .blocked(reason: TypedTextLanding.secureReplaceRefusal(label: label))
        }
        let edgeHeight: CGFloat = element.elementType == .textView ? 0.98 : 0.5
        func settledRemaining() -> String {
            TypedTextLanding.remainingText(value: settledValue(of: element).value, placeholder: element.placeholderValue)
        }
        let trailing = CGVector(dx: 0.98, dy: edgeHeight)
        var remaining = ""
        var pass = 1
        while true {
            let before = pass == 1 ? TypedTextLanding.remainingText(value: element.value as? String, placeholder: element.placeholderValue) : remaining
            guard deleteText(of: element, tappingAt: trailing) else {
                return .blocked(reason: TypedTextLanding.unfocusedReplaceRefusal(label: label))
            }
            remaining = settledRemaining()
            guard TypedTextLanding.shouldRetryTrailingEdge(before: before, after: remaining, pass: pass) else { break }
            pass += 1
        }
        if !remaining.isEmpty {
            guard deleteText(of: element, tappingAt: CGVector(dx: 0.02, dy: edgeHeight)) else {
                return .blocked(reason: TypedTextLanding.unfocusedReplaceRefusal(label: label))
            }
            remaining = settledRemaining()
        }
        if let refusal = TypedTextLanding.stillHeldRefusal(label: label, remaining: remaining) {
            return .blocked(reason: refusal)
        }
        if !text.isEmpty {
            element.typeText(text)
        }
        if let refusal = TypedTextLanding.replaceRefusal(label: label, text: text, after: settledValue(of: element).value, placeholder: element.placeholderValue) {
            return .blocked(reason: refusal)
        }
        return .landedOn(field.target.node)
    }

    /// Reads `element`'s value until it has not changed for `fieldQuiet` (at most the step's quiet), or `fieldBudget` (at most the step's budget) has passed by the wall clock (SimWalk#214).
    ///
    /// An app may rewrite a field a beat after it changed (a formatter on the next run loop), and a read straight after `typeText` races that. A field's value is not late-loading content, so it gets a short quiet of its own rather than the screen's: a step reads up to eight times (six trailing passes, the leading edge, the read-back), and a screen settled over seconds would multiply that. The clock is `Date()`, so the reads' own time counts against the budget. The decision is `FieldValueSettle`'s, in the core; this loop keeps only the reads and the clock.
    private func settledValue(of element: XCUIElement) -> FieldValueSettle {
        var settle = FieldValueSettle(quiet: min(quiet, Self.fieldQuiet), budget: min(budget, Self.fieldBudget))
        let started = Date()
        while true {
            let elapsed = Date().timeIntervalSince(started)
            settle.record(Self.liveRead(or: nil) { element.value as? String }, at: elapsed)
            if settle.isSettled(at: elapsed) {
                return settle
            }
            Thread.sleep(forTimeInterval: Self.settleInterval)
        }
    }

    /// How long a field's value must hold still before it is judged (SimWalk#214).
    private static var fieldQuiet: TimeInterval {
        0.25
    }

    /// The longest one read of a field's value waits for it to hold still (SimWalk#214).
    private static var fieldBudget: TimeInterval {
        2
    }

    /// Taps `element` at `offset` of its frame, then sends a delete keystroke for each character it reads; false, with nothing typed, when the tap left the field without keyboard focus.
    ///
    /// A coordinate tap neither scrolls the field into view nor checks what it lands on (a key of the keyboard an earlier `type` left up, a button at the field's edge), and `typeText` into a field without focus is an XCTest failure that ends the whole walk, where a refusal is one step that did not land.
    private func deleteText(of element: XCUIElement, tappingAt offset: CGVector) -> Bool {
        element.coordinate(withNormalizedOffset: offset).tap()
        guard Self.liveRead(or: false, { (element.value(forKey: "hasKeyboardFocus") as? Bool) == true }) else {
            return false
        }
        let count = TypedTextLanding.deleteKeystrokes(value: element.value as? String)
        if count > 0 {
            element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
        }
        return true
    }
}
