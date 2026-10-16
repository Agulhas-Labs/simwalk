//
// Copyright © Agulhas Labs
//

import Foundation
import RegexBuilder

/// Which element a route step's label names, when more than one element carries it (SimWalk#17).
///
/// **The first match in tree order used to win, and on a real screen the first match is chrome.** On a category landing, `tap 'Sleep'` (the category's name) matched the navigation bar — whose identifier is the screen title — and the large title before it reached the row labelled `Sleep, Nothing earlier to compare with` that opens the record. The tap landed on the bar, the screen did not move, and the step came back UNREACHABLE looking exactly like a missing route. The only step that worked named the row's data-carrying note, which changes the moment the store does.
///
/// **Ranked, and still deterministic.** Every candidate is ranked first by the tier it matched in — literally (a whole label, an identifier, a leading comma-separated component), then the same with its no-break spaces read as spaces, then a `{n}` pattern, then a lead-in to its data, each consulted only when nothing at all matched in the tier before — then by what it is — a control that can navigate (a button, a cell, a link, a switch) in the screen, above a control inside a bar (a tab item, a toolbar's Edit), above content (static text, images, containers), above chrome and anything that cannot take a tap (a navigation bar, a tab bar, a toolbar themselves, text inside them, a disabled or zero-sized element) — and, among literal matches, a whole label or identifier above a leading component. The best rank wins, and **a tie at the best rank goes to the first in tree order**, which is what the tool always did.
///
/// **Ties are not refused, and that was measured rather than assumed.** Refusing them was the other option on the issue, and the first cut did: the next full walk of a field walkbook lost two screens, whose `tap 'Coastal Cruise'` names a family of eighteen rides and means the first — the newest, at the top of the list. Tapping "the first row that starts with this" is how a walkbook reaches a list's head without pinning its data, which is the whole point of matching a leading component. So a tie keeps tree order, and when the step then fails to land its reason says it was a tie, and among how many.
///
/// The match mirrors the runner's predicate for three of its cases — `label == X OR identifier == X OR label BEGINSWITH "X, "` — so a snapshot and the live query agree on what matched there, and a candidate matched that way carries the index the live query binds it at.
///
/// **A data-carrying label is addressed on purpose, with `{n}` (SimWalk#13).** A filter chip reads `Sailing 22`, and the count is the store's: there is no chip whose label is free of data, and no comma to end a leading component on. `'Sailing {n}'` names it — the literal text exactly, each `{n}` standing for one number — and matches the whole label. It is opt-in rather than inferred because the inferred version is the one that was wrong: on a Workouts screen `tap 'Sailing'` reaches the *By sport* row `Sailing, Wednesday · 1.48 km in 8 min, 1`, a whole leading component, and must go on doing so. **It is a tier below every literal match**, because braces are not otherwise special in a label: a step reading `'Week {n}'` reached an element labelled `Week {n}` — or `Week {n}, summary`, or a text `Week {n}` — before the placeholder existed, and still does, wherever `Week 3` sits and whatever it is. The pattern is consulted only when nothing on screen matches literally, and acted on only once the step's lookup has run out with nothing literal found (`RouteTargetTracker`), so a literal match arriving at any point before that still wins.
///
/// **A lead-in to a label's data is the last resort (SimWalk#9).** `'Sail, 12 August'` against `'Sail, 12 August 14:50 · 3.43 km, 12 min'` has no comma between the date and the time it runs into. So when nothing on screen matches in any of the ways above — not a control, not content, not even chrome — a label that *starts* with the step's text is considered, and only if what follows is data: a run of separators (whitespace or a `·`) and then a decimal digit. `'Heart Rate'` never reaches `'Heart Rate Variability'`, which is a different named thing, and `'Distance 3'` never reaches `'Distance 3.43 km'`, whose number it cuts in half. A lead-in never takes a step away from an element it used to reach: it is consulted only where a screen's answer used to be *nothing*, and acted on only at a moment the step used to report nothing — once the lookup has run out with nothing literal found (`RouteTargetTracker`). It is also held to more than the other matches, because it is looser than they are: a tie refuses and names what it found rather than guessing which of two dates was meant — an element and anything drawn inside it with the same label (a wrapper and its text, a cell and the button inset in it) counting once.
public struct RouteTarget {
    /// Every element under `tree` that `label` matches in any tier — literally (its whole label, its identifier, a leading component), with its no-break spaces read as spaces, by a `{n}` pattern, or as a lead-in to its data — each in the first way that applies, the root itself excluded, as a live query of its descendants excludes it, in tree order.
    public static func candidates(labelled label: String, in tree: AXNode, reaching reach: Reach = .control) -> [Candidate] {
        let pattern = pattern(for: label)
        return collect(in: tree, reaching: reach) { node in
            match(of: label, on: node, pattern: pattern)
        }
    }

    /// The element a step labelled `label` should act on, or why there is none.
    ///
    /// Only the best tier that matched anything is considered, so a looser tier cannot outrank a stricter one whatever kinds each lands on; and a lead-in, the loosest, refuses a tie rather than taking the first.
    ///
    /// **A `type` step whose label names fields of more than one type refuses** rather than ranking between them. The lookup it replaced took the first search field carrying the label, then the first text field, then a secure field, then a text view; ranking can prefer an in-screen text field to a search field in the navigation bar, or an enabled field of one type to a disabled one of another — a different field than before, typed into and reported as landed. No captured tree holds two such fields to replay against, so the step names both instead of guessing.
    public static func choose(labelled label: String, in tree: AXNode, reaching reach: Reach = .control) -> Choice {
        let all = candidates(labelled: label, in: tree, reaching: reach)
        guard let best = all.map(\.rank).min() else { return .none }
        let tier = all.filter { $0.match.tier == best.match.tier }
        if reach == .textEntry, Set(tier.map(\.node.type)).count > 1 {
            return .ambiguous(tier)
        }
        let top = tier.filter { $0.rank == best }
        guard best.match == .prefix else {
            return top.first.map { .chosen($0, among: tier) } ?? .none
        }
        let spots = distinctSpots(top)
        guard spots.count == 1, let target = spots.first else { return .ambiguous(spots) }
        return .chosen(target, among: tier)
    }

    /// Walks `tree` in order, keeping every node `matching` answers for, with the bar each sits inside, where it sits, and — for a match the live predicate can express — the index that predicate binds it at.
    private static func collect(in tree: AXNode, reaching reach: Reach, matching: (AXNode) -> Match?) -> [Candidate] {
        var found: [Candidate] = []
        var indexed = 0
        func visit(_ node: AXNode, at path: [Int], inside bar: String?) {
            if reach.admits(node), let match = matching(node) {
                let index = reach.bindsByIndex && match.isLivePredicate ? indexed : nil
                if index != nil {
                    indexed += 1
                }
                found.append(Candidate(node: node, match: match, index: index, insideBar: bar, reach: reach, path: path))
            }
            let enclosing = bar ?? (barTypes.contains(node.type) ? node.type : nil)
            for (position, child) in node.children.enumerated() {
                visit(child, at: path + [position], inside: enclosing)
            }
        }
        for (position, child) in tree.children.enumerated() {
            visit(child, at: [position], inside: nil)
        }
        return found
    }

    /// Whether a step labelled `label` would match `node` in any tier — what `ControlCoverage` counts as a route covering a control, so coverage and the runner agree on what a label reaches.
    static func matches(_ label: String, _ node: AXNode) -> Bool {
        match(of: label, on: node, pattern: pattern(for: label)) != nil
    }

    /// Whether `text` is `label` as a whole, with no-break spaces read as spaces on both sides or, where `label` holds `{n}`, a number in its place.
    ///
    /// In no looser way: no leading component, no lead-in. What ``TapLanding`` asks of a navigation bar's title, where the prefix tiers of ``matches(_:_:)`` would widen "landed" (SimWalk#126).
    static func namesWhole(_ label: String, _ text: String) -> Bool {
        if readingSpacesAsSpaces(text) == readingSpacesAsSpaces(label) {
            return true
        }
        guard let pattern = pattern(for: label) else { return false }
        return (try? pattern.wholeMatch(in: text)) != nil
    }

    private static func match(of label: String, on node: AXNode, pattern: Regex<Substring>?) -> Match? {
        if node.label == label {
            return .label
        }
        if node.identifier == label {
            return .identifier
        }
        if node.label?.hasPrefix("\(label), ") == true {
            return .leadingComponent
        }
        if let nodeLabel = node.label {
            let spoken = readingSpacesAsSpaces(label)
            let drawn = readingSpacesAsSpaces(nodeLabel)
            if drawn == spoken || drawn.hasPrefix("\(spoken), ") {
                return .spacing
            }
        }
        if let pattern, let nodeLabel = node.label, (try? pattern.wholeMatch(in: nodeLabel)) != nil {
            return .pattern
        }
        return isLeadIn(label, to: node) ? .prefix : nil
    }

    /// `text` with each no-break (U+00A0) and narrow no-break (U+202F) space read as an ordinary space — what a `.spacing` match compares on both sides (SimWalk#99).
    ///
    /// Only those two: they are the spaces an app writes so a name never wraps (`CO₂ level`), and the ones a person authoring a walkbook cannot tell from a space. A thin space (U+2009) is a visible difference and is not read as one.
    fileprivate static func readingSpacesAsSpaces(_ text: String) -> String {
        String(text.map { $0 == "\u{00A0}" || $0 == "\u{202F}" ? " " : $0 })
    }

    /// Whether `label` begins `node`'s label and what follows it is data: a run of separators — whitespace or a `·` — and then a decimal digit.
    ///
    /// **The digit is the whole point.** A space alone would let `'Heart Rate'` reach `'Heart Rate Variability'`, a different named thing that happens to share two words, and anything short of a digit would let it reach `'Heart Rate (bpm)'`; a separator run ending in a digit says the step's text is where the words stop and the figures start. A decimal digit (`isDecimalDigit`), in any script a number formatter writes — not a superscript, a fraction, a circled number or a numeral like `五`, none of which starts a figure. A label that continues straight into a digit or a decimal point is not reached either — `'Sailing 2'` is not a lead-in to `'Sailing 22'`, nor `'Distance 3'` to `'Distance 3.43 km'` — because a step ending partway through a number has pinned part of the data it was meant to leave out.
    ///
    /// **A comma is not a separator here, for the same reason.** A comma and a space already end a leading component, which is a literal match and never reaches this; any other comma before a digit is inside the number — `'Steps 4'` against `'Steps 4,210'`, `'Distance 3'` against a decimal comma's `'Distance 3,43 km'`.
    ///
    /// **Nor is a group separator between two digits.** French, Russian, Swedish and their neighbours group a number's digits with a non-breaking, narrow non-breaking or thin space (`groupSeparators`), which is whitespace to `Character` — so `'Steps 4'` against `'Steps 4 210'` is the comma's case again in another locale, and a step whose text ends in a digit is not led in by one of those. After a word, the same space still separates it from the figures: `'Sailing'` reaches `'Sailing 22'`.
    private static func isLeadIn(_ label: String, to node: AXNode) -> Bool {
        guard !label.isEmpty, let nodeLabel = node.label, nodeLabel.hasPrefix(label) else { return false }
        let rest = nodeLabel.dropFirst(label.count)
        let separators = rest.prefix { $0.isWhitespace || $0 == "·" }
        guard !separators.isEmpty, let next = rest.dropFirst(separators.count).first, isDecimalDigit(next) else { return false }
        let groupsANumber = label.last.map(isDecimalDigit) == true && separators.allSatisfy(groupSeparators.contains)
        return !groupsANumber
    }

    /// Whether `character` is a decimal digit — `0`–`9` or its counterpart in another script (`٣`, `३`, `３`), read as the `{n}` pattern's digit class reads it: by its first scalar's numeric type.
    ///
    /// Not `Character.isNumber`, which also takes `²`, `½`, `①`, `五` and `Ⅻ` — characters that are numbers without being digits of a figure a formatter draws.
    private static func isDecimalDigit(_ character: Character) -> Bool {
        character.unicodeScalars.first?.properties.numericType == .decimal
    }

    /// The spaces a number formatter groups digits with in the locales that group by space: non-breaking (U+00A0), narrow non-breaking (U+202F) and thin (U+2009).
    private static let groupSeparators: Set<Character> = ["\u{00A0}", "\u{202F}", "\u{2009}"]

    /// `label` as a pattern for a whole label, each `{n}` in it standing for one number — or `nil` when it names no placeholder.
    private static func pattern(for label: String) -> Regex<Substring>? {
        let literals = label.split(separator: placeholder, omittingEmptySubsequences: false).map(String.init)
        guard literals.count > 1, let first = literals.first else { return nil }
        let number = Self.number
        return literals.dropFirst().reduce(Regex { first }) { pattern, literal in
            Regex {
                pattern
                number
                literal
            }
        }
    }

    /// What `{n}` stands for: one number, optionally signed, whose digits may be grouped or broken by a decimal point or comma — `22`, `1,234`, `3.43`, `3,43`, `+0.62`, `−0.62`.
    ///
    /// **Decimal digits, in any script** (`Unicode.GeneralCategory.decimalNumber`, the class `isDecimalDigit` reads): `٣` and `３` are digits of a figure, `²`, `½`, `①`, `五` and `Ⅻ` are not — and `.digit`, which is `Character.isNumber`, takes all five.
    ///
    /// **Only a `.` or a `,` joins its digits.** A number grouped with a space (`1 234` in French, drawn with a narrow non-breaking space), an apostrophe (`1’234` in Swiss German) or the Arabic separators (`٣٫٤`, `١٬٢٣٤`) is not one number here, so a label drawn that way is not matched — the step finds nothing rather than something else.
    static var number: Regex<Substring> {
        Regex {
            Optionally {
                CharacterClass.anyOf("+-−")
            }
            OneOrMore(CharacterClass.generalCategory(.decimalNumber))
            ZeroOrMore {
                CharacterClass.anyOf(".,")
                OneOrMore(CharacterClass.generalCategory(.decimalNumber))
            }
        }
    }

    /// One candidate per element on screen, the first in tree order (the outermost) standing for the rest.
    ///
    /// An element and whatever is drawn inside it carrying the same label — a wrapper and its text, a table cell and the button inset in it — are one thing to tap, and so are two elements with one label at one frame. Only candidates that already rank equally are folded, so a control inside a wrapper of lesser rank is never folded away into it.
    private static func distinctSpots(_ candidates: [Candidate]) -> [Candidate] {
        candidates.reduce(into: []) { spots, candidate in
            let isSameElement = spots.contains { spot in
                spot.node.label == candidate.node.label
                    && (candidate.path.starts(with: spot.path) || spot.node.frame == candidate.node.frame)
            }
            if !isSameElement {
                spots.append(candidate)
            }
        }
    }

    /// The placeholder a step writes where a label carries a number that changes with the data.
    public static var placeholder: String {
        "{n}"
    }

    /// Element types a person taps to act — the ones a route step is almost always reaching for.
    static let controlTypes: Set<String> = ["Button", "Cell", "Link", "Switch"]

    /// Element types that take typed text — the only ones a `type` step considers, so it never lands on the container a search field is drawn inside.
    static let textEntryTypes: Set<String> = ["SearchField", "TextField", "SecureTextField", "TextView"]

    /// Element types that frame a screen rather than sit in it; a tap on one navigates nowhere.
    static let chromeTypes: Set<String> = ["NavigationBar", "TabBar", "Toolbar", "Window", "Application"]

    /// The bars among them, whose own controls rank below the screen's controls and above its content.
    ///
    /// The SimWalk#17 review, twice. First: a tab item labelled `Workouts` is a whole-label control, and ranked as one it would beat the row `Workouts, 18` — and the tab it switches to changes the screen's identity, so the wrong tab would be captured under the screen's id with nothing to say so. A route that means a tab says `tab`, and one that means going back says `back`. Second: ranking them *with* the bar went too far — a navigation bar's Edit or a toolbar's Done then lost to a StaticText carrying the same word — so a bar's control sits between the two.
    static let barTypes: Set<String> = ["NavigationBar", "TabBar", "Toolbar"]
}

public extension RouteTarget {
    /// One element a step's label matched.
    struct Candidate: Equatable, Sendable {
        /// The element, as the snapshot read it — its children are not part of the answer and are dropped.
        public let node: AXNode
        /// How the label matched it.
        public let match: Match
        /// Its position among the matches of the runner's live predicate — `label == X OR identifier == X OR label BEGINSWITH "X, "` over the app's descendants — in tree order, which is the index that query binds it at.
        ///
        /// `nil` where that query would not return it at all: a spacing match (SimWalk#99), a `{n}` pattern or a lead-in, which the predicate cannot express, and anything a `type` step reaches, which is bound among the text fields rather than among every descendant. The runner binds those by the label and frame the snapshot recorded instead.
        public let index: Int?
        /// The bar it sits inside — `TabBar`, `NavigationBar`, `Toolbar` — or `nil` when it sits in the screen.
        public let insideBar: String?
        /// What the step that matched it is reaching for, which decides what counts as a control.
        public let reach: Reach
        /// Where it sits: its position among its parent's children at each level below the root, outermost first — so an element drawn inside another reads as inside it.
        public let path: [Int]

        public init(node: AXNode, match: Match, index: Int?, insideBar: String? = nil, reach: Reach = .control, path: [Int] = []) {
            var leaf = node
            leaf.children = []
            self.node = leaf
            self.match = match
            self.index = index
            self.insideBar = insideBar
            self.reach = reach
            self.path = path
        }

        /// Lower is better: what kind of element it is first, then how its label matched.
        public var rank: Rank {
            Rank(kind: kind, match: match)
        }

        /// Whether it is a control a person acts on — for a `type` step, a field that takes text — and so the kind of thing a route step is waiting to find.
        public var isControl: Bool {
            kind == .control
        }

        /// Whether it is a control inside a bar rather than the screen itself — a tab item, or a navigation bar's or toolbar's own control (SimWalk#24).
        public var isBarControl: Bool {
            kind == .barControl
        }

        /// "a NavigationBar identified 'Sleep'" — what a refusal names, in the words the element answered to.
        public var description: String {
            let named = switch match {
            case .identifier: "identified '\(node.identifier ?? "")'"
            case .spacing: "labelled '\(RouteTarget.readingSpacesAsSpaces(node.label ?? ""))' (its label differs from the step only in a no-break space)"
            default: "labelled '\(node.label ?? "")'"
            }
            let qualifier = if let insideBar {
                " in the \(insideBar)"
            } else if kind == .unusable, !RouteTarget.chromeTypes.contains(node.type) {
                node.isEnabled ? " (zero-sized)" : " (disabled)"
            } else {
                ""
            }
            return "a \(node.type) \(named)\(qualifier)"
        }

        /// Whether a live element read while scrolling towards this one is still this one: the label the snapshot recorded — or its identifier, for a match on that — at the same width, height and horizontal position.
        ///
        /// **A bound element is not a fixed element.** The runner binds by an index among a query's matches, and every read resolves that index again; once a lazy list recycles the rows above, the same index can name a later row. A swipe moves an element up or down the screen and nothing else, so a scroll that finds its element's label changed, or its frame changed in any other way, has lost it — and says so rather than landing on whatever the index names now.
        public func isStill(label: String?, identifier: String?, frame: AXNode.Frame) -> Bool {
            let named = match == .identifier ? identifier == node.identifier : label == node.label
            return named
                && abs(frame.x - node.frame.x) < 0.5
                && abs(frame.width - node.frame.width) < 0.5
                && abs(frame.height - node.frame.height) < 0.5
        }

        fileprivate var kind: Kind {
            if RouteTarget.chromeTypes.contains(node.type) || !node.isEnabled || node.frame.width <= 0 || node.frame.height <= 0 {
                return .unusable
            }
            let isControl = reach.controlTypes.contains(node.type)
            return switch (isControl, insideBar != nil) {
            case (true, false): .control
            case (true, true): reach.reachesIntoBars ? .barControl : .unusable
            case (false, false): .content
            case (false, true): .unusable
            }
        }
    }

    /// What a step is reaching for, which decides which elements it considers, which of them count as controls, and what it may accept once the screen holds still.
    enum Reach: Equatable, Sendable {
        /// A `tap`: a control that can navigate.
        case control
        /// A `scrollTo`: anything carrying the label that can be brought on screen — a control is still preferred, but a heading is a perfectly good place to arrive.
        case anything
        /// A `type`: a field that takes text, and nothing else.
        case textEntry

        /// The element types that count as controls for this reach.
        var controlTypes: Set<String> {
            self == .textEntry ? RouteTarget.textEntryTypes : RouteTarget.controlTypes
        }

        /// Whether a node is considered at all — every node, except for a `type` step, which never considers anything that cannot take text.
        func admits(_ node: AXNode) -> Bool {
            self != .textEntry || RouteTarget.textEntryTypes.contains(node.type)
        }

        /// Whether the runner binds what this reach chose by the live predicate's index — every reach but `type`, which binds among the text fields.
        var bindsByIndex: Bool {
            self != .textEntry
        }

        /// Whether a label that resolves to nothing is swiped towards before the step gives up — for a `tap` and a `scrollTo`, yes; for a `type`, no (SimWalk#104).
        ///
        /// One route has to work across a screen's states, and Dynamic Type moves rows below the fold of a lazy list: at AX XXXL a pushed `Form` built two cells and the button in its third section was not in the tree at all, so `tap` refused in the states where the light one captured. A `tap` never scrolled, so it could only refuse; it now seeks as `scrollTo` does (SimWalk#74). A text field was not asked for.
        public var seeksWhenAbsent: Bool {
            self != .textEntry
        }

        /// Whether a control inside a bar is worth reaching — for a tap or a field, yes, below the screen's own; for a `scrollTo`, no.
        ///
        /// A bar is always on screen, so a `scrollTo` that chose a tab item would land without scrolling at all: `tab 'Today'` then `scrollTo 'Workouts'` would stop at the top of Today, on the tab item `Workouts`, instead of scrolling to the card of that name. For a scroll a bar's control ranks with the bar, below content — so the card wins **whenever it is in the tree**.
        ///
        /// **Not when it is not.** A lazy list builds a card only once it is scrolled near, so until then the tab item is the only element carrying the word; it is still chosen, as the best of what matched, and it is on screen, so the step lands on it without scrolling — as it did before any of this ranking. Ranking cannot reach an element the tree does not hold yet; that needs the scroll to search before it chooses.
        var reachesIntoBars: Bool {
            self != .anything
        }
    }

    /// How a label matched an element.
    enum Match: Equatable, Sendable {
        /// The whole label.
        case label
        /// The identifier.
        case identifier
        /// The leading comma-separated component of a composed label.
        case leadingComponent
        /// The whole label, or its leading component, once a no-break space (U+00A0) or narrow no-break space (U+202F) is read as a space on both sides (SimWalk#99) — `'CO₂ level'` against `'CO₂\u{00A0}level, 38.8 ppm'`, which an app writes so the name never wraps and its author cannot see.
        ///
        /// Identifiers are not normalised: an identifier is a name the app chose, compared as written.
        case spacing
        /// The whole label against a step naming it with `{n}` where a number goes (SimWalk#13) — `'Sailing {n}'` against a filter chip's `'Sailing 22'`.
        case pattern
        /// The start of the label, running into its data — the last resort, when nothing matches in any other way (SimWalk#9): `'Sail, 12 August'` against `'Sail, 12 August 14:50 · 3.43 km, 12 min'`.
        case prefix

        /// Which tier the match is in: what the step says literally, then the same with its no-break spaces read as spaces, then a `{n}` pattern, then a lead-in to the label's data — ranked above an element's kind, so a looser match on a control never beats a stricter one on content.
        ///
        /// A later tier is consulted only when nothing on screen matched in an earlier one (SimWalk#9, SimWalk#13, SimWalk#99): the spacing match, the lead-in and the pattern each exist to reach a label nothing else can, and neither may take a step away from an element it reached before them. A label that literally reads `'Week {n}'` is the placeholder's case of that.
        fileprivate var tier: Int {
            switch self {
            case .label, .identifier, .leadingComponent: 0
            case .spacing: 1
            case .pattern: 2
            case .prefix: 3
            }
        }

        /// Within the literal tier, a whole label or identifier is the author naming this element outright; a leading component is naming a family of them.
        ///
        /// A pattern and a lead-in are each the only match in their tier, and a spacing match — a whole label or a leading component — shares its tier only with its own kind, so each is only ever ranked against its own kind.
        fileprivate var precedence: Int {
            switch self {
            case .label, .identifier, .spacing, .pattern, .prefix: 0
            case .leadingComponent: 1
            }
        }

        /// Whether the runner's live predicate returns an element matched this way — so the element can be bound at that query's index.
        ///
        /// A spacing match is not one: the predicate compares exact characters and would not return the no-break variant, so it is bound by the label and frame the snapshot recorded, as a pattern or a lead-in is (SimWalk#99).
        fileprivate var isLivePredicate: Bool {
            switch self {
            case .label, .identifier, .leadingComponent: true
            case .spacing, .pattern, .prefix: false
            }
        }
    }

    /// A candidate's standing: the tier its match is in, then its kind, then its match within the tier.
    struct Rank: Comparable, Sendable {
        fileprivate let kind: Kind
        fileprivate let match: Match

        /// Its standing within its tier: kind first, then the match's precedence.
        private var withinTier: (kind: Int, precedence: Int) {
            (kind.rawValue, match.precedence)
        }

        public static func == (lhs: Rank, rhs: Rank) -> Bool {
            lhs.match.tier == rhs.match.tier && lhs.withinTier == rhs.withinTier
        }

        public static func < (lhs: Rank, rhs: Rank) -> Bool {
            guard lhs.match.tier == rhs.match.tier else { return lhs.match.tier < rhs.match.tier }
            return lhs.withinTier < rhs.withinTier
        }
    }

    /// What a step's label resolves to.
    enum Choice: Equatable, Sendable {
        /// The element to act on — the best-ranked, first in tree order among equals — and every element the label matched in the same tier it did (literally, with its no-break spaces read as spaces, by a `{n}` pattern, or as a lead-in).
        case chosen(Candidate, among: [Candidate])
        /// More than one element ranks best and the step does not choose between them: two lead-ins to their data, neither named outright (SimWalk#9), or — for a `type` step — fields of more than one type (`RouteTarget.choose`).
        ///
        /// Unlike a tie on a whole leading component — which keeps meaning "the first of a family" and is never refused — a lead-in this loose has not earned that trust, so it refuses rather than guessing which of two dates was meant. Its candidates are one per element on screen: an element and anything drawn inside it with the same label count once.
        case ambiguous([Candidate])
        /// Nothing carries the label.
        case none

        /// Whether the label matched something literally — a whole label, an identifier or a leading component, the matches the runner's live predicate always made.
        ///
        /// This is what starts a step's budget (`RouteTargetTracker`): the lookup it replaced gave a step with no such match the whole lookup to find one, and only a literal match started the shorter wait for something better. A spacing match, a `{n}` pattern or a lead-in does not, so neither can end a step sooner than it used to end.
        public var matchedLiterally: Bool {
            switch self {
            case let .chosen(candidate, _): candidate.match.tier == 0
            case let .ambiguous(candidates): candidates.contains { $0.match.tier == 0 }
            case .none: false
            }
        }

        /// Whether waiting longer cannot improve the answer: the best match is literal, and it is a control in the screen — or, for a `scrollTo`, content, which is as good a place to arrive as a control.
        ///
        /// Anything else is worth another look while a screen is still arriving — its navigation bar exists the instant it is pushed, and the row a step is reaching for can come a beat later. **A spacing match, a `{n}` pattern or a lead-in never settles**, not even on a control: each is what the step found while nothing matched literally, and an element that does can still be arriving — tapping the neighbour first would pass every later check.
        ///
        /// **A `scrollTo` settles on content** because it arrives as soon as the element it names exists, as it always did: waiting for a control to load beside a heading of the same name would cost the quiet period on every scroll — up to the whole lookup on a screen that never holds still — to choose between two places that are, to a scroll, the same place. It still waits on a bar's control or chrome, which a scroll can only "arrive" at by not scrolling.
        public var isSettled: Bool {
            guard case let .chosen(candidate, _) = self, candidate.match.tier == 0 else { return false }
            return candidate.isControl || (candidate.reach == .anything && candidate.kind == .content)
        }

        /// Whether this choice may be taken once the hierarchy has held still for the quiet period, rather than waiting out the rest of the step's budget (SimWalk#24).
        ///
        /// A control inside a bar — `Edit`, `Done` — ranks below the screen's own controls so a row still loading can beat it; a row still loading also changes the tree, so once the tree has been still for as long as the screen needs to settle, nothing is left to arrive. A `scrollTo` extends the same to a bar's control or chrome, the literal matches it does not settle on.
        ///
        /// **Literal matches only.** A spacing match, a `{n}` pattern or a lead-in is what a step found where the lookup it replaced found nothing, and that lookup went on reading for the whole of it; taking one early — on stillness, or on the budget — would act where a literal match arriving later used to be found. So none qualifies, and none does nothing.
        public var acceptsOnceStill: Bool {
            guard case let .chosen(candidate, _) = self, candidate.match.tier == 0 else { return false }
            return candidate.isBarControl || candidate.reach == .anything
        }

        /// What a bind that missed this choice's element may do with `tree`, one fresh read of the screen: bind the same element again, look again for a different one, or report the miss.
        ///
        /// **Only a spacing match, a `{n}` pattern or a lead-in earns the second look.** Each is bound by the label the snapshot recorded (`Candidate.index` is `nil`), and the labels the pattern and the lead-in exist for are exactly the ones that change: a chip's `Sailing 22` can read `Sailing 23` by the time it is bound, and a bind by its old label then finds nothing. So the step's label is chosen again, by the same rules and for the same reach — a `type` step's second look is still among fields — and what that finds decides it (`rebinding(to:)`). A literal match is bound at the live predicate's index and checked by frame, so its miss means the element moved, and that is what the step reports.
        public func rebinding(labelled label: String, in tree: AXNode) -> Rebinding {
            guard case let .chosen(candidate, _) = self else { return .final }
            return rebinding(to: RouteTarget.choose(labelled: label, in: tree, reaching: candidate.reach))
        }

        /// What a bind that missed this choice's element may do with `fresh`, the step's label chosen again.
        ///
        /// **The same element, and only that, is bound without a word** — the same place in the tree, matched the same way, whatever its label now reads: that is a chip whose count ticked. A row inserted above it puts another element at that place, and one matching literally there is not the chip moved on. A different element is never acted on silently, because it is not what the tracker chose: a row matching literally that arrived after the step's lookup had run out, a neighbour that moved into the gap. The runner reads the screen until the tracker settles once more and asks again, and a second different answer is a refusal naming both (`Rebinding.different`). Anything but a choice — nothing, or a tie — leaves the miss standing. Once, never a loop.
        public func rebinding(to fresh: Choice) -> Rebinding {
            guard case let .chosen(candidate, _) = self, candidate.match.tier > 0, case let .chosen(retarget, _) = fresh else { return .final }
            let isSameElement = retarget.path == candidate.path && retarget.match == candidate.match
            return isSameElement ? .same(fresh) : .different(from: candidate, to: retarget)
        }

        /// Why a step on this choice did not land, for the UNREACHABLE that reports it.
        ///
        /// Names what matched, because an UNREACHABLE that reads like a missing route sends its reader to the walkbook when the label was there all along and taken by something that does not navigate. Said compactly — a list of eighteen rides is eighteen of one thing, not eighteen sentences.
        public func reason(for label: String) -> String {
            missReason(for: label, saying: "the screen did not change")
        }

        /// Why a tap on a keyboard key did not land (SimWalk#94): the screen did not change *and* the focused field's value did not, said as both, because a key's evidence is the field and a refusal naming only the screen sends its reader to check the wrong thing.
        ///
        /// `fieldHadFocus` is whether a field held keyboard focus when the tap was read — "no field had keyboard focus" is a different fault from a field that took nothing.
        public func keyReason(for label: String, fieldHadFocus: Bool) -> String {
            let checked = fieldHadFocus ? "neither the screen nor the focused field's value changed" : "the screen did not change, and no field had keyboard focus"
            return missReason(for: label, saying: checked)
        }

        private func missReason(for label: String, saying checked: String) -> String {
            switch self {
            case let .chosen(candidate, all):
                let tied = all.filter { $0.rank == candidate.rank }.count
                let tie = tied > 1 ? " — the first of \(tied) that ranked equally —" : ","
                let rest = all.filter { $0 != candidate }
                let others = rest.isEmpty ? "" : " (it also matched \(Self.tally(rest)))"
                return "tapped \(candidate.description)\(tie) and \(checked)\(others)"
            case let .ambiguous(candidates) where Set(candidates.map(\.node.type)).count > 1 && candidates.allSatisfy { $0.reach == .textEntry }:
                return "'\(label)' names fields of more than one type, and a type step does not choose between them: \(Self.tally(candidates))"
            case let .ambiguous(candidates):
                return "'\(label)' only begins the labels of \(candidates.count) elements, equally, and names none of them outright: \(Self.tally(candidates))"
            case .none:
                return "nothing on screen is labelled or identified '\(label)'"
            }
        }

        /// Candidates described once per distinct description and counted, in the order they first appear, naming at most three.
        private static func tally(_ candidates: [Candidate]) -> String {
            var order: [String] = []
            var counts: [String: Int] = [:]
            for description in candidates.map(\.description) {
                if counts[description] == nil {
                    order.append(description)
                }
                counts[description, default: 0] += 1
            }
            let named = order.prefix(3).map { description in
                let count = counts[description] ?? 1
                return count > 1 ? "\(count) × \(description)" : description
            }
            let unnamed = order.dropFirst(3).reduce(0) { $0 + (counts[$1] ?? 0) }
            return (named + (unnamed > 0 ? ["\(unnamed) more"] : [])).joined(separator: "; ")
        }
    }

    /// What a bind that missed its element may do instead (`Choice.rebinding`).
    enum Rebinding: Equatable, Sendable {
        /// The miss stands: a literal match's, or a second look that found nothing to act on.
        case final
        /// The same element, its label moved on — bind this choice instead.
        case same(Choice)
        /// A different element than the one chosen.
        ///
        /// On the first, single read the runner looks again until the tracker settles; on that second look it refuses.
        case different(from: Candidate, to: Candidate)

        /// Why a step that looked twice and found a different element both times acts on neither, naming both — or `nil` for anything else.
        public var reason: String? {
            guard case let .different(from, to) = self else { return nil }
            return "\(from.description) moved before it could be bound, and reading the screen again chose a different element, \(to.description) — a step never acts on an element it did not choose"
        }
    }
}

private extension RouteTarget {
    /// What kind of element a candidate is, best first.
    enum Kind: Int {
        case control
        case barControl
        case content
        case unusable
    }
}
