//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// What a tap changed on a screen it did not leave: a lasting selection or enablement lands it and shows in the step's delta as `~` lines (SimWalk#251), and a tapped element that only moved is told apart from one that pulsed (#253).
struct SameScreenChangeTests {
    // MARK: - Trait changes

    /// **A tapped tile that became selected lands the tap, and the delta names it and the button it enabled** (SimWalk#251): the picker's tap changes no structure, so identity alone refused it.
    @Test
    func aTileGainingSelectedLandsAndItAndTheButtonItEnabledShowAsChangedLines() {
        let before = Self.picker(selected: false, checkEnabled: false)
        let after = Self.picker(selected: true, checkEnabled: true)
        let tile = Self.button("6", y: 300, selected: false, enabled: true)

        let changes = SameScreenChange.traitChanges(from: before, to: after)
        let tapped = SameScreenChange.tappedTraitChange(from: before, to: after, tapped: tile)
        let landing = TapLanding.decide(arrived: false, tappedTraitChanged: tapped != nil, wasSelected: false, hittable: false, titled: false)
        let delta = ScreenDelta(from: before, to: after)

        #expect(landing == .landed)
        #expect(tapped?.words == "selected")
        #expect(changes.map(\.words) == ["selected", "enabled"])
        #expect(delta.residue == [
            "delta: 0 appeared, 0 disappeared, 2 changed",
            "~ 6 · Button · 16,300 80×80 · selected",
            "~ Check · Button · 16,700 370×50 · enabled",
        ])
        #expect(!delta.isEmpty)
    }

    /// **A tap that must change nothing lands when the screen stayed and the tapped element's traits did too** (SimWalk#268), whatever changed elsewhere.
    @Test
    func aTapThatMustChangeNothingLandsWhenNothingOfItsOwnChanged() {
        let before = Self.picker(selected: false, checkEnabled: false)
        let after = Self.picker(selected: false, checkEnabled: true)
        let tile = Self.button("6", y: 300, selected: false, enabled: true)
        let tapped = SameScreenChange.tappedTraitChange(from: before, to: after, tapped: tile)

        #expect(TapLanding.decideUnchanged(screenChange: nil, tappedTraitChange: tapped, tapped: "a Button labelled '6'") == .landed)
    }

    /// **A tap that must change nothing on a keyboard key is refused with a reason of its own**, since a key is tapped to type and so cannot change nothing (SimWalk#268).
    @Test
    func aTapThatMustChangeNothingOnAKeyboardKeyIsRefusedWithItsOwnReason() {
        #expect(TapLanding.unchangedKeyRefusal(label: "6")
            == "'6' is a keyboard key: a key is tapped to type, so a tap on one cannot be held to changing nothing — use a plain tap")
    }

    /// **A tap that must change nothing is refused when the screen changed, or the tapped element became selected or enabled**, saying which.
    @Test
    func aTapThatMustChangeNothingIsRefusedWhenSomethingOfItsOwnChanged() {
        let before = Self.picker(selected: false, checkEnabled: false)
        let tile = Self.button("6", y: 300, selected: false, enabled: true)
        let selected = SameScreenChange.tappedTraitChange(from: before, to: Self.picker(selected: true, checkEnabled: false), tapped: tile)
        let target = "a Button labelled '6'"

        let menu = Self.screen([Self.button("6", y: 300, selected: false, enabled: true), Self.button("Open details", y: 500, selected: false, enabled: true)])
        #expect(TapLanding.decideUnchanged(screenChange: ScreenStructureChange.between(Self.screen([tile]), menu), tappedTraitChange: nil, tapped: target)
            == .refused(reason: "tapped a Button labelled '6' expecting nothing to change, but the screen changed: 'Open details' appeared"))
        #expect(TapLanding.decideUnchanged(screenChange: nil, tappedTraitChange: selected, tapped: target)
            == .refused(reason: "tapped a Button labelled '6' expecting nothing to change, but it became selected"))
        let enabled = SameScreenChange.TraitChange(node: tile, selected: false, enabled: true)
        #expect(TapLanding.decideUnchanged(screenChange: nil, tappedTraitChange: enabled, tapped: target)
            == .refused(reason: "tapped a Button labelled '6' expecting nothing to change, but it became deselected and enabled"))
    }

    /// **A tap on a dead control does not land because another control became enabled meanwhile**: after a `type` step, a form's debounced validation can enable its Submit button during the next tap's budget, which is the form's doing, not the tap's.
    ///
    /// The change still shows in the delta.
    @Test
    func aDeadControlsTapDoesNotLandWhenAnotherControlBecomesEnabled() {
        let before = Self.picker(selected: false, checkEnabled: false)
        let after = Self.picker(selected: false, checkEnabled: true)
        let deadTile = Self.button("7", y: 400, selected: false, enabled: true)

        let tapped = SameScreenChange.tappedTraitChange(from: before, to: after, tapped: deadTile)
        let landing = TapLanding.decide(arrived: false, tappedTraitChanged: tapped != nil, wasSelected: false, hittable: true, titled: false)

        #expect(tapped == nil)
        #expect(landing == .notLanded)
        #expect(ScreenDelta(from: before, to: after).changed == ["Check · Button · 16,700 370×50 · enabled"])
    }

    /// **The tapped element is found by name and nearest centre, so a snapshot frame a pulse has since scaled still finds its change.**
    @Test
    func theTappedElementsChangeIsFoundByItsNameNotItsExactFrame() {
        let before = Self.picker(selected: false, checkEnabled: false)
        let after = Self.picker(selected: true, checkEnabled: false)
        let snapshot = AXNode(type: "Button", frame: AXNode.Frame(x: 14, y: 298, width: 84, height: 84), label: "6")

        #expect(SameScreenChange.tappedTraitChange(from: before, to: after, tapped: snapshot)?.words == "selected")
    }

    /// **The tapped element is found without its identifier** (SimWalk#279), as `ScreenIdentity` reads a screen: the snapshot the step bound can be from before the identifier filled in.
    @Test
    func theTappedElementsChangeIsFoundWhateverItsIdentifierReadInTheSnapshot() {
        func identified(_ tree: AXNode) -> AXNode {
            var tree = tree
            tree.children[0].children[0].identifier = "tile-6"
            return tree
        }
        let before = identified(Self.picker(selected: false, checkEnabled: false))
        let after = identified(Self.picker(selected: true, checkEnabled: false))
        let snapshot = AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 300, width: 80, height: 80), label: "6")

        #expect(SameScreenChange.tappedTraitChange(from: before, to: after, tapped: snapshot)?.words == "selected")
    }

    /// **An element read again a pulse apart neither appeared nor disappeared**: seen live on the pulse screen, a guarded tile tap's delta listed the pulsing Start button as one `+` and one `-` line.
    ///
    /// Only its trait changes are left.
    @Test
    func anElementReadAPulseApartIsNeitherAppearedNorDisappeared() {
        let start = { (frame: AXNode.Frame) in AXNode(type: "Button", frame: frame, label: "Start") }
        let before = Self.screen([start(AXNode.Frame(x: 170, y: 184, width: 62, height: 35)), Self.button("6", y: 300, selected: false, enabled: true)])
        let after = Self.screen([start(AXNode.Frame(x: 169, y: 183, width: 65, height: 36)), Self.button("6", y: 300, selected: true, enabled: true)])

        #expect(ScreenDelta(from: before, to: after).residue == [
            "delta: 0 appeared, 0 disappeared, 1 changed",
            "~ 6 · Button · 16,300 80×80 · selected",
        ])
    }

    /// **An element that really slid is still one line gone and one come**, however alike the two lines' text.
    @Test
    func anElementThatSlidIsStillDisappearedAndAppeared() {
        let start = { (y: Double) in AXNode(type: "Button", frame: AXNode.Frame(x: 170, y: y, width: 62, height: 35), label: "Start") }

        #expect(ScreenDelta(from: Self.screen([start(184)]), to: Self.screen([start(260)])).residue == [
            "delta: 1 appeared, 1 disappeared",
            "+ Start · Button · 170,260 62×35",
            "- Start · Button · 170,184 62×35",
        ])
    }

    /// **A pulse apart pairs only elements of the same label, value and type**: a different value at a steady frame is a changed element.
    @Test
    func aDifferentValueAtASteadyFrameIsStillDisappearedAndAppeared() {
        let field = { (value: String) in AXNode(type: "TextField", frame: AXNode.Frame(x: 16, y: 200, width: 300, height: 44), label: "Email", value: value) }

        #expect(ScreenDelta(from: Self.screen([field("a")]), to: Self.screen([field("ab")])).residue == [
            "delta: 1 appeared, 1 disappeared",
            "+ Email = ab · TextField · 16,200 300×44",
            "- Email = a · TextField · 16,200 300×44",
        ])
    }

    /// **Two changes on one node share its line, and the reverse changes read as such.**
    @Test
    func twoChangesOnOneNodeAreJoinedAndTheReverseIsWorded() {
        let before = Self.screen([Self.button("6", y: 300, selected: true, enabled: true)])
        let after = Self.screen([Self.button("6", y: 300, selected: false, enabled: false)])

        #expect(SameScreenChange.traitChanges(from: before, to: after).map(\.words) == ["not selected, disabled"])
    }

    /// **Between two different screens nothing is a trait change**: the nodes do not pair up, and a screen that was left needs no `~` line.
    @Test
    func screensWhoseIdentitiesDifferHaveNoChangedLines() {
        let before = Self.picker(selected: false, checkEnabled: false)
        let after = Self.screen([Self.button("6", y: 300, selected: true, enabled: true), Self.button("Done", y: 700, selected: false, enabled: true)])

        #expect(SameScreenChange.traitChanges(from: before, to: after).isEmpty)
        #expect(ScreenDelta(from: before, to: after).changedCount == 0)
        #expect(!ScreenDelta(from: before, to: after).residue.contains { $0.hasPrefix("~") })
    }

    /// **A delta with no trait change reads byte for byte as before the changed lines existed**, so every existing answer is unchanged.
    @Test
    func aDeltaWithNoTraitChangeReadsAsItDidBefore() {
        let before = Self.screen([Self.button("6", y: 300, selected: false, enabled: true)])
        let after = Self.screen([Self.button("6", y: 310, selected: false, enabled: true)])

        #expect(ScreenDelta(from: before, to: after).residue == [
            "delta: 1 appeared, 1 disappeared",
            "+ 6 · Button · 16,310 80×80",
            "- 6 · Button · 16,300 80×80",
        ])
        #expect(ScreenDelta(from: before, to: before).residue == ["delta: nothing appeared or disappeared"])
    }

    /// **Changed lines are counted in full and listed to the same cap as the others.**
    @Test
    func changedLinesAreCappedAsTheOthersAre() {
        let before = Self.screen((0 ..< 25).map { Self.button("Tile \($0)", y: Double(20 + $0 * 30), selected: false, enabled: true) })
        let after = Self.screen((0 ..< 25).map { Self.button("Tile \($0)", y: Double(20 + $0 * 30), selected: true, enabled: true) })

        let delta = ScreenDelta(from: before, to: after)

        #expect(delta.changedCount == 25)
        #expect(delta.changed.count == ScreenDelta.cap)
        #expect(delta.residue.last == "~ … 5 more — `session read` lists them all")
    }

    /// **A delta written before the changed lines existed still decodes**, with none.
    @Test
    func aDeltaWrittenBeforeTheChangedLinesStillDecodes() throws {
        let json = #"{"appearedCount":0,"disappearedCount":0,"appeared":[],"disappeared":[]}"#

        let delta = try JSONDecoder().decode(ScreenDelta.self, from: Data(json.utf8))

        #expect(delta.changedCount == 0)
        #expect(delta.changed.isEmpty)
    }

    // MARK: - Scroll only

    /// **A tapped element that moved 91 points on a screen that stayed was scrolled, and the reason says from where to where** (SimWalk#253).
    @Test
    func aTappedNodeThatMovedIsReportedAsScrolledWithItsPositions() throws {
        let node = Self.node(x: 165, y: 296)
        let before = Self.screen([node])
        let after = Self.screen([Self.node(x: 164, y: 205)])

        let scroll = try #require(SameScreenChange.scroll(from: before, to: after, tapped: node))

        #expect(scroll.from == node.frame)
        #expect(scroll.to == AXNode.Frame(x: 164, y: 205, width: 72, height: 72))
        #expect(scroll.reason(tapped: "a Button labelled 'Start'") == "tapped a Button labelled 'Start', but the screen only scrolled: it moved from 165,296 to 164,205")
    }

    /// **A tapped element that pulsed (6%) did not move**: it is no scroll, and the refusal stays the usual one.
    @Test
    func aTappedNodeThatPulsedIsNotAScroll() {
        let node = Self.node(x: 165, y: 296)
        let pulsed = AXNode.Frame(x: 165 - 72 * 0.03, y: 296 - 72 * 0.03, width: 72 * 1.06, height: 72 * 1.06)
        let after = Self.screen([AXNode(type: "Button", frame: pulsed, label: "Start")])

        #expect(SameScreenChange.scroll(from: Self.screen([node]), to: after, tapped: node) == nil)
    }

    /// **A screen that was left is no scroll**, however far the tapped element's namesake sits from where it was.
    @Test
    func aScreenThatWasLeftIsNoScroll() {
        let node = Self.node(x: 165, y: 296)
        let after = Self.screen([Self.node(x: 164, y: 205), Self.button("Done", y: 700, selected: false, enabled: true)])

        #expect(SameScreenChange.scroll(from: Self.screen([node]), to: after, tapped: node) == nil)
    }

    /// **The tapped element is found by what identity compares, so a snapshot frame a pulse has since scaled still finds it.**
    @Test
    func theTappedNodeIsFoundByItsNameNotItsExactFrame() {
        let snapshot = AXNode(type: "Button", frame: AXNode.Frame(x: 163, y: 294, width: 76, height: 76), label: "Start")
        let before = Self.screen([Self.button("Start", y: 600, selected: false, enabled: true), Self.node(x: 165, y: 296)])
        let after = Self.screen([Self.button("Start", y: 600, selected: false, enabled: true), Self.node(x: 164, y: 205)])

        #expect(SameScreenChange.scroll(from: before, to: after, tapped: snapshot)?.to.y == 205)
    }

    // MARK: - Fixtures

    static let screenFrame = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)

    static func screen(_ children: [AXNode]) -> AXNode {
        AXNode(type: "Application", frame: screenFrame, label: "RouteFixture", children: [AXNode(type: "Other", frame: screenFrame, identifier: "pulse", children: children)])
    }

    static func button(_ label: String, y: Double, selected: Bool, enabled: Bool) -> AXNode {
        AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: y, width: 80, height: 80), label: label, isSelected: selected, isEnabled: enabled)
    }

    static func node(x: Double, y: Double) -> AXNode {
        AXNode(type: "Button", frame: AXNode.Frame(x: x, y: y, width: 72, height: 72), label: "Start")
    }

    /// A tile picker: a tile, its neighbour, and a Check button that enables once a tile is chosen.
    static func picker(selected: Bool, checkEnabled: Bool) -> AXNode {
        screen([
            button("6", y: 300, selected: selected, enabled: true),
            button("7", y: 400, selected: false, enabled: true),
            AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 700, width: 370, height: 50), label: "Check", isEnabled: checkEnabled),
        ])
    }
}
