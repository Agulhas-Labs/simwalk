//
// Copyright © Agulhas Labs
//

import Foundation

/// Answers one screen's content from a capture bundle: its screen identifier (``ScreenIdentifier``) and the text on screen, in accessibility order — the question after a walk is almost always about (SimWalk#20).
///
/// **On screen means inside the capture's own frame, and nothing stronger.** A screenshot is the viewport — 1206 × 2622 px is the 402 × 874 pt frame the tree is rooted at — while a scrolled screen's tree reaches well below it, so an element whose frame does not intersect the root's is left out of the text and counted instead: "does the screen show X" is never answered yes for text the screenshot cannot hold. Inside the frame is not the same as unobscured — text under a bar, or behind a presented sheet, still counts — and the answer claims only the first.
///
/// **Priced against the one screenshot it stands in for, never the tree.** A reader answering a text question opens the screenshot or reads the tree, never both, so this answer is weighed against `imgTokens` alone (§4 review) — pricing it against the tree too would claim a saving nobody would actually have taken, on top of the one this answer actually replaces.
///
/// **Text only.** A capsule and a line can carry the same label, and a match on text cannot tell them apart — the residue says so on its last line, so a question about visual form still goes to the screenshot.
public struct BundleScreenQuery {
    private let bundle: CaptureBundle

    /// What this query is logged and dispatched as everywhere it is reached — the CLI's own name for it, and the one word `simwalk usage` prices a one-screen answer under, kept in this one place so the CLI command and the MCP face that reaches it through `inspect` cannot drift apart on the spelling.
    public static var logName: String {
        "bundle screen"
    }

    public init(_ bundle: CaptureBundle) {
        self.bundle = bundle
    }

    /// The answer for one screen.
    ///
    /// - Parameters:
    ///   - step: the screen's 1-based position in the walk (as `bundle inspect` numbers it), or the screen's own id.
    ///   - state: which of the screen's captured states to read, by slug; with none named, a screen holding several answers for the first and the verdict names the rest (SimWalk#101).
    ///   - match: narrows the text to elements whose label or value contains it, case-insensitively — on screen or off it.
    ///   - all: lists the off-screen elements too, after the on-screen ones, each marked `(off screen)`.
    ///   - tree: lists the nodes `match` names with identifier, frame, selected flag and ancestors (``ScreenTreeListing``) instead of the text.
    ///   - bars: lists the tab, tool and navigation bars the same way, alone or with `match`.
    public func answer(step: String, state: String? = nil, match: String? = nil, all: Bool = false, tree listsTree: Bool = false, bars: Bool = false) throws -> Answer {
        let (screen, position) = try Self.screen(at: step, in: bundle.manifest)
        let capture = try Self.capture(at: position, in: screen, state: state)
        let tree = try bundle.axTree(for: capture)
        let text = if listsTree || bars {
            ScreenTreeListing.listing(of: tree, match: match, bars: bars, listingOffScreen: all)
        } else {
            Self.text(of: tree, match: match, listingOffScreen: all, offScreenHint: "--all lists them", stillNeeding: CaptureBundleLayout.screenshotFileName)
        }
        let detail = "step \(position) '\(screen.id)' [\(capture.state.slug)]\(Self.alsoClause(state: state, screen: screen)) — \(text.clause)"

        return Answer(
            header: CaptureBundleHeader.line(of: bundle),
            verdict: Self.verdict(capture, detail: detail),
            residue: text.residue,
            weighing: ContextSaving.weighing(bundle, capture: capture)
        )
    }

    /// What the verdict adds when no state was named and the screen holds several: which one this is, and the others to ask for.
    ///
    /// A multi-state screen used to refuse, so every read cost a second call carrying a state id the first call's refusal had to supply (SimWalk#101). The first state is the answer and the rest are named, so the choice is still the caller's and never silent.
    private static func alsoClause(state: String?, screen: CaptureManifest.ScreenRecord) -> String {
        guard state == nil, screen.captures.count > 1 else { return "" }
        let others = screen.captures.dropFirst().map(\.state.slug).joined(separator: ", ")
        return " (1 of \(screen.captures.count) states; also \(others); pick one with --state)"
    }

    /// One tree's text as this answer lists it: the residue — the screen's text elements in accessibility order, then the line saying what text cannot answer — and the verdict's clause naming the root and how much text answered.
    ///
    /// Shared with ``LiveScreenQuery``, so a tree read live off the device and one read back from a bundle are listed by the same code and `--match` narrows both alike. `screenshot` is what the last line sends a visual question to — the bundle's own file here, a screenshot still to be taken for a live read.
    ///
    /// **`--match` searches the whole tree, on screen and off** (SimWalk#101): at large type most of a page sits below the fold, and finding the element an audit finding named should not take a hand-written walk of `ax-tree.json`. On-screen hits come first, then off-screen ones marked `(off screen)`. Without a match, off-screen elements are listed only when `listingOffScreen` asks; otherwise they are counted, and `offScreenHint` (the flag that lists them, when the caller has one) is named.
    static func text(
        of tree: AXNode,
        match: String?,
        listingOffScreen: Bool = false,
        offScreenHint: String? = nil,
        stillNeeding screenshot: String
    ) -> (residue: [String], clause: String) {
        let (onScreen, offScreen) = deduplicated(tree)
        let listed = match.map { text in onScreen.filter { element($0, contains: text) } } ?? onScreen
        let offScreenHits = match.map { text in offScreen.filter { element($0, contains: text) } } ?? offScreen
        let offListed = match != nil || listingOffScreen ? offScreenHits : []

        var residue = listed.map(line) + offListed.map { "\(line($0)) (off screen)" }
        residue.append("")
        residue.append("text only — colour, shape and visual emphasis (a capsule vs. a line) still need \(screenshot)")

        let countClause: String
        if let match {
            let more = offListed.isEmpty ? "" : ", and \(offListed.count) off screen (listed)"
            countClause = "\(listed.count) of \(onScreen.count) on-screen elements match '\(match)'\(more)"
        } else {
            let more = if offScreen.isEmpty {
                ""
            } else if listingOffScreen {
                "; \(offScreen.count) off screen (listed)"
            } else {
                "; \(offScreen.count) off screen, omitted\(offScreenHint.map { " — \($0)" } ?? "")"
            }
            countClause = "\(listed.count) text element\(listed.count == 1 ? "" : "s") on screen\(more)"
        }
        return (residue, "root \(rootClause(tree)), \(countClause)")
    }

    /// The screen's on-screen text elements, one line each, exactly as the residue lists them — what ``ScreenDelta`` compares before and after a step.
    static func lines(of tree: AXNode) -> [String] {
        deduplicated(tree).onScreen.map(line)
    }

    /// The verdict: every qualification the one capture this reads carries, then `detail` — which screen, which state, its root, and how much text answered.
    private static func verdict(_ capture: CaptureManifest.StateCapture, detail: String) -> AnswerVerdict {
        let qualifications = [
            AnswerVerdict.qualification(capture.axTreeSettled == false && capture.axTreeHasContent != false ? 1 : 0, "capture", "taken before the tree settled"),
            AnswerVerdict.qualification(capture.axTreeHasContent == false ? 1 : 0, "capture", "holding the app's chrome and nothing else"),
            AnswerVerdict.qualification(capture.unverifiedAxes?.isEmpty == false ? 1 : 0, "capture", "with a state axis set and unverified"),
        ].compactMap(\.self)
        return AnswerVerdict.reporting(qualifications: qualifications, detail: detail)
    }

    /// The screen's identifier as the verdict states it, saying where it was read whenever that is anywhere but a container's own identifier on the screen — a presentation covering the screen, a navigation bar's title (localised), or an identifier every element of one container shares (no stable identity) — and, when there is none, why: a presentation carrying none answers "presented, unidentified" rather than the covered screen's, and a framework identifier refused is named rather than hidden behind "no container carries one".
    static func rootClause(_ tree: AXNode) -> String {
        let reading = ScreenIdentifier.reading(tree, fallingBackToUnstable: true)
        let onPresentation = reading.presentation.map { ", on \($0.description)" } ?? ""
        guard let identifier = reading.identifier else {
            let refusal = reading.refused.isEmpty ? nil : "refused framework identifier\(reading.refused.count == 1 ? "" : "s") "
                + reading.refused.map { "'\($0)'" }.joined(separator: ", ")
            if let presentation = reading.presentation {
                return "(presented, unidentified — \(refusal.map { "on \(presentation.description), \($0)" } ?? "nothing on \(presentation.description) carries a usable identifier"))"
            }
            return "(no identifier — \(refusal ?? "no container in the content carries one"))"
        }
        return switch identifier.source {
        case .content:
            reading.presentation.map { "'\(identifier.value)' (on \($0.description))" } ?? "'\(identifier.value)'"
        case .navigationBar:
            "'\(identifier.value)' (the navigation bar's title\(onPresentation) — localised; set an accessibilityIdentifier for a stable expect:)"
        case .propagated:
            "'\(identifier.value)' (shared by every element of one container\(onPresentation) — not a stable screen identity)"
        }
    }

    /// The screen `step` names — a 1-based position in the walk, or the screen's own id — and its position either way, so the verdict can always say "step N" even when the caller asked by id.
    ///
    /// A step that is both a valid position and the exact id of a *different* screen is refused rather than read one way: no walkbook this tool has seen writes ids like that, and silently preferring either reading is a guess at which screen the caller meant.
    private static func screen(at step: String, in manifest: CaptureManifest) throws -> (screen: CaptureManifest.ScreenRecord, position: Int) {
        let byID = manifest.screens.enumerated().filter { $0.element.id == step }
        if let position = Int(step), position >= 1, position <= manifest.screens.count {
            if byID.count == 1, let other = byID.first, other.offset + 1 != position {
                throw BundleScreenError.ambiguousStep(step: step, positionScreenID: manifest.screens[position - 1].id, idPosition: other.offset + 1)
            }
            return (manifest.screens[position - 1], position)
        }
        guard byID.count == 1, let match = byID.first else {
            if let position = Int(step) {
                throw BundleScreenError.stepOutOfRange(step: position, screenCount: manifest.screens.count)
            }
            throw BundleScreenError.screenIDNotFound(id: step, available: manifest.screens.map(\.id))
        }
        return (match.element, match.offset + 1)
    }

    /// The one capture `step` answers for: the named state, or the screen's first when none was named (``alsoClause(state:screen:)`` names the rest).
    private static func capture(at position: Int, in screen: CaptureManifest.ScreenRecord, state: String?) throws -> CaptureManifest.StateCapture {
        guard !screen.captures.isEmpty else {
            throw BundleScreenError.screenNotCaptured(step: position, screenID: screen.id, outcome: outcomeLabel(screen.outcome))
        }
        if let state {
            guard let capture = screen.captures.first(where: { $0.state.slug == state }) else {
                let available = screen.captures.map(\.state.slug)
                if screen.refusedStates?.contains(where: { $0.slug == state }) == true {
                    throw BundleScreenError.stateRefused(step: position, screenID: screen.id, requested: state, available: available)
                }
                throw BundleScreenError.stateNotFound(step: position, screenID: screen.id, requested: state, available: available)
            }
            return capture
        }
        return screen.captures[0]
    }

    /// The short tag `bundle inspect` prints for a screen's outcome, named the same way here so a refusal points a reader at a word they have already seen.
    private static func outcomeLabel(_ outcome: ScreenOutcome) -> String {
        switch outcome {
        case .captured: "captured" // unreachable in practice: CaptureManifestValidator holds `.captured` to at least one capture.
        case let .unreachable(_, _, _, state): state.map { "UNREACHABLE \($0.clause)" } ?? "UNREACHABLE"
        case .buildMismatch: "REFUSED, build mismatch"
        case .captureFailed: "CAPTURE FAILED"
        case .stateNotApplied: "REFUSED, state not applied"
        case .unexpectedScreen: "REFUSED, not the screen its walkbook expected"
        }
    }

    /// The screen's own text-bearing elements — a label, or failing one a value (a switch's state with no label of its own) — in accessibility order, collapsed three ways:
    ///
    /// - **An exact repeat** — the same label, value, type and frame twice — is one element. On the real captures this shape is a scroll bar's duplicate sibling, and it is the commoner of the two collapses.
    /// - **An element that restates an ancestor** — the same label *and* the same value, at a frame the ancestor's own encloses (a settings row and its title, a labelled cell and the text inside it) — is one element, and the line kept is the **more specific type's**: an interactive kind (``interactiveTypes``) over anything else, and anything over a bare `Other`, because the type is a fact a reader and `bundle audit` act on — a `Share` button is not an `Other` that happens to say "Share". A value differing between the two keeps both, since dropping either would drop a fact.
    /// - **An unlabelled value an ancestor already carries** is dropped: it restates that ancestor's line with nothing of its own to add.
    ///
    /// **The screen is split before anything collapses.** Each element is on screen or off it by its own frame, and an off-screen element never stands in for an on-screen one: it may collapse into an on-screen line it restates, but never replace that line with its own type, and an on-screen value is dropped only for an on-screen ancestor carrying it. Otherwise a row straddling the bottom edge collapsed into its more specific same-label child, and when that child sat wholly below the edge the row's line vanished as off screen while the row was plainly showing.
    ///
    /// The app root itself is never a candidate — its own label is the app's display name, which is not text on the screen — so this walks `tree.children`, never `tree` itself.
    private static func deduplicated(_ tree: AXNode) -> (onScreen: [AXNode], offScreen: [AXNode]) {
        struct Key: Hashable {
            let label: String?
            let value: String?
            let type: String
            let x: Double
            let y: Double
            let width: Double
            let height: Double

            init(_ node: AXNode) {
                label = BundleScreenQuery.nonEmpty(node.label)
                value = BundleScreenQuery.nonEmpty(node.value)
                type = node.type
                x = node.frame.x
                y = node.frame.y
                width = node.frame.width
                height = node.frame.height
            }
        }
        var listedAt: [Key: Int] = [:]
        var result: [(node: AXNode, onScreen: Bool)] = []
        let isOnScreen = onScreenTest(for: tree)

        /// Lists `node`, or points at the line an exact repeat of it already has — which is on the same side of the edge, having the same frame.
        func list(_ node: AXNode) -> Int {
            let key = Key(node)
            if let index = listedAt[key] {
                return index
            }
            result.append((node, isOnScreen(node)))
            listedAt[key] = result.count - 1
            return result.count - 1
        }

        /// `listed` is the line that stands for each ancestor — its own, or the one it collapsed into — and `nil` for one with no text.
        func visit(_ node: AXNode, ancestors: [(node: AXNode, listed: Int?)]) {
            let onScreen = isOnScreen(node)
            var listed: Int?
            if nonEmpty(node.label) != nil {
                if let index = ancestors.last(where: { $0.listed != nil && restates(node, $0.node) })?.listed {
                    if onScreen || !result[index].onScreen, specificity(node) > specificity(result[index].node) {
                        result[index].node = node
                        listedAt[Key(node)] = index
                    }
                    listed = index
                } else {
                    listed = list(node)
                }
            } else if let value = nonEmpty(node.value),
                      !ancestors.contains(where: { nonEmpty($0.node.value) == value && (!onScreen || isOnScreen($0.node)) })
            {
                listed = list(node)
            }
            node.children.forEach { visit($0, ancestors: ancestors + [(node, listed)]) }
        }
        tree.children.forEach { visit($0, ancestors: []) }
        return (result.filter(\.onScreen).map(\.node), result.filter { !$0.onScreen }.map(\.node))
    }

    /// The element types a reader acts on — kept over a same-text container when the two collapse.
    private static let interactiveTypes: Set<String> = ["Button", "Link", "Switch", "Slider", "TextField", "SecureTextField", "TextView", "Cell"]

    /// How much an element's type says: an interactive kind most, a bare `Other` least.
    private static func specificity(_ node: AXNode) -> Int {
        if interactiveTypes.contains(node.type) {
            return 2
        }
        return node.type == "Other" ? 0 : 1
    }

    /// Whether `node` says nothing `ancestor` does not: the same label and value, inside the ancestor's frame.
    private static func restates(_ node: AXNode, _ ancestor: AXNode) -> Bool {
        nonEmpty(ancestor.label) == nonEmpty(node.label)
            && nonEmpty(ancestor.value) == nonEmpty(node.value)
            && contains(ancestor.frame, node.frame)
    }

    /// Whether `inner` sits entirely inside `outer` — the frame test behind collapsing an element that restates its ancestor.
    private static func contains(_ outer: AXNode.Frame, _ inner: AXNode.Frame) -> Bool {
        inner.x >= outer.x
            && inner.y >= outer.y
            && inner.x + inner.width <= outer.x + outer.width
            && inner.y + inner.height <= outer.y + outer.height
    }

    /// The test both `bundle screen` answers share for "on screen": the node's frame intersects the tree's ``AXNode/screenBounds`` — the root's frame, or its window's where the root reports none — read once.
    static func onScreenTest(for tree: AXNode) -> (AXNode) -> Bool {
        let bounds = tree.screenBounds
        return { intersects(bounds, $0.frame) }
    }

    /// Whether any of `inner` falls inside `outer` — what "on screen" means here: a line half-scrolled past the edge is on screen, one wholly below it is not.
    static func intersects(_ outer: AXNode.Frame, _ inner: AXNode.Frame) -> Bool {
        inner.x < outer.x + outer.width
            && inner.x + inner.width > outer.x
            && inner.y < outer.y + outer.height
            && inner.y + inner.height > outer.y
    }

    /// Whether `--match`'s text is in the element's label or in its value — the two halves of the line a reader was shown.
    private static func element(_ element: AXNode, contains text: String) -> Bool {
        [element.label, element.value].contains { $0?.range(of: text, options: .caseInsensitive) != nil }
    }

    /// One element's residue line: its label (or `(no label)`), its value when it carries one — a switch's state, a chart's summary — its type, and its frame.
    static func line(_ element: AXNode) -> String {
        let label = nonEmpty(element.label) ?? "(no label)"
        let text = nonEmpty(element.value).map { "\(label) = \($0)" } ?? label
        return "\(text) · \(element.type) · \(frameText(element.frame))"
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    /// A frame as a reader can act on without opening the screenshot: whole points, `x,y w×h`.
    static func frameText(_ frame: AXNode.Frame) -> String {
        "\(point(frame.x)),\(point(frame.y)) \(point(frame.width))×\(point(frame.height))"
    }

    private static func point(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}
