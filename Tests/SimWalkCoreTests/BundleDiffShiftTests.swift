//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// `bundle diff` over layout shifts (SimWalk#67, M3): a shift on one side only is a flag, matched by element identity; the settle time is never compared.
struct BundleDiffShiftTests {
    private static let light = Walkbook.CaptureState(theme: .light)
    private static let dark = Walkbook.CaptureState(theme: .dark)

    @Test
    func theSameShiftOnBothSidesIsNoFlag() throws {
        let diff = try Self.diff(reference: [Self.shift("Row 2")], run: [Self.shift("Row 2")])

        #expect(diff.flagCount == 0)
        #expect(diff.screens.first?.shiftFlags == [])
        #expect(diff.screens.first?.shiftNotes == nil)
    }

    @Test
    func aShiftOnlyInTheRunIsOneFlagNamingTheRun() throws {
        let diff = try Self.diff(reference: [], run: [Self.shift("Row 2", dy: 72)])
        let screen = try #require(diff.screens.first)
        let lines = BundleDiffRendering.shiftLines(of: screen)

        #expect(diff.flagCount == 1)
        #expect(screen.shiftFlags?.map(\.side) == [.run])
        #expect(lines == ["  shift only in run s/light: Button 'Row 2' moved 0,+72 pt — cause: inserted Other 'banner'"])
    }

    @Test
    func aShiftOnlyInTheReferenceNamesTheReferenceAndAnUncausedOneSaysSo() throws {
        let diff = try Self.diff(reference: [Self.shift("Row 2", dy: -30, cause: nil)], run: [])
        let lines = try BundleDiffRendering.shiftLines(of: #require(diff.screens.first))

        #expect(lines == ["  shift only in reference s/light: Button 'Row 2' moved 0,-30 pt — cause: no cause named"])
    }

    @Test
    func anIdentityOccurringTwiceInTheRunAndOnceInTheReferenceIsOneFlag() throws {
        let diff = try Self.diff(reference: [Self.shift("Row 2")], run: [Self.shift("Row 2"), Self.shift("Row 2")])

        #expect(diff.flagCount == 1)
        #expect(diff.screens.first?.shiftFlags?.map(\.side) == [.run])
    }

    @Test
    func theSameIdentityWithOtherPathBoxesAndTimeIsNoFlag() throws {
        let moved = Self.shift("Row 2", dy: 10, path: [0, 5], at: 900)
        let diff = try Self.diff(reference: [Self.shift("Row 2", dy: 72, path: [0, 1], at: 100)], run: [moved])

        #expect(diff.flagCount == 0)
    }

    /// **`within` is not identity**: the name of what holds an anonymous element is a value that changes between runs, and a baseline recorded before it existed has none — neither is a shift that changed.
    @Test(arguments: [nil, "Inbox, 4 unread"])
    func anAnonymousShiftMatchesWhateverItsHolderIsNamed(runWithin: String?) throws {
        func cell(within: String?) -> CaptureManifest.Motion.Shift {
            CaptureManifest.Motion.Shift(
                element: CaptureManifest.Motion.Element(type: "Cell", identifier: nil, label: nil, path: [0, 2], within: within),
                before: AXNode.Frame(x: 0, y: 100, width: 300, height: 44),
                after: AXNode.Frame(x: 0, y: 172, width: 300, height: 44),
                movedAtMilliseconds: 300,
                cause: nil
            )
        }
        let diff = try Self.diff(reference: [cell(within: "Inbox, 3 unread")], run: [cell(within: runWithin)])

        #expect(diff.flagCount == 0)
    }

    @Test
    func anotherIdentityIsAFlag() throws {
        let diff = try Self.diff(reference: [Self.shift("Row 2")], run: [Self.shift("Row 3")])

        #expect(diff.flagCount == 2)
    }

    @Test
    func oneSideWithoutAShiftRecordIsANoteAndNoFlag() throws {
        let diff = try Self.diff(reference: nil, run: [Self.shift("Row 2")])
        let screen = try #require(diff.screens.first)

        #expect(diff.flagCount == 0)
        #expect(screen.shiftFlags == nil)
        #expect(BundleDiffRendering.shiftLines(of: screen) == ["  s/light: motion not compared: no shift record on reference"])
    }

    @Test
    func aMotionRecordWithoutShiftsIsNotARecord() throws {
        let bare = CaptureManifest.Motion(settleMilliseconds: 10, readIntervalMilliseconds: 50, readCount: 2)
        let diff = try Self.diff(referenceMotion: [bare], runMotion: [Self.motion([Self.shift("Row 2")])])

        #expect(diff.flagCount == 0)
        #expect(diff.screens.first?.shiftNotes == [ScreenDiff.ShiftNote(slug: "light", missingSide: .reference)])
    }

    @Test
    func neitherSideRecordingShiftsSaysNothing() throws {
        let diff = try Self.diff(reference: nil, run: nil)
        let screen = try #require(diff.screens.first)

        #expect(screen.shiftFlags == nil)
        #expect(screen.shiftNotes == nil)
        #expect(BundleDiffRendering.shiftLines(of: screen).isEmpty)
    }

    @Test
    func settleTimeAndReadFiguresAreNeverCompared() throws {
        let reference = CaptureManifest.Motion(settleMilliseconds: 10, readIntervalMilliseconds: 50, readCount: 2, landingMilliseconds: 5, shifts: [])
        let run = CaptureManifest.Motion(settleMilliseconds: 900, readIntervalMilliseconds: 100, readCount: 9, measuredReadSpacingMilliseconds: 120, landingMilliseconds: 400, shifts: [])
        let diff = try Self.diff(referenceMotion: [reference], runMotion: [run])

        #expect(diff.flagCount == 0)
        #expect(try BundleDiffRendering.shiftLines(of: #require(diff.screens.first)).isEmpty)
    }

    @Test
    func aStateCapturedOnOneSideOnlyIsNotCompared() throws {
        let (referenceDirectory, runDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let reference = try Self.bundle(in: referenceDirectory, captures: [(Self.light, Self.motion([Self.shift("Row 2")]))])
        let run = try Self.bundle(in: runDirectory, captures: [(Self.light, Self.motion([Self.shift("Row 2")])), (Self.dark, Self.motion([Self.shift("Row 9")]))])

        let diff = BundleDiff.compare(run: run, against: reference)

        #expect(diff.flagCount == 0)
        #expect(diff.screens.first?.unpairedStates.map(\.slug) == [Self.dark.slug])
    }

    @Test
    func theCountIncludesShiftFlagsAndOnlyShiftFlagsLeaveAScreenOffTheCleanLine() throws {
        let flagged = try Self.diff(reference: [], run: [Self.shift("Row 2")])
        let clean = try Self.diff(reference: [Self.shift("Row 2")], run: [Self.shift("Row 2")])

        #expect(flagged.screens.first?.flagCount == 1)
        #expect(BundleDiffRendering.cleanLine(flagged).isEmpty)
        #expect(BundleDiffRendering.cleanLine(clean) == ["no form difference: s"])
    }

    /// A shift line prints after every state block of its screen, so it must name the screen: under two screens a bare state slug reads as the previous screen's.
    @Test
    func aShiftLineAndANoteNameTheirScreenAndState() throws {
        let (referenceDirectory, runDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let reference = try Self.twoScreens(in: referenceDirectory, a: Self.motion([Self.shift("Row 1")]), b: nil)
        let run = try Self.twoScreens(in: runDirectory, a: Self.motion([Self.shift("Row 1"), Self.shift("Row 9")]), b: Self.motion([Self.shift("Row 2")]))

        let lines = BundleDiffRendering.lines(of: BundleDiff.compare(run: run, against: reference))

        #expect(lines.contains("  shift only in run A/light: Button 'Row 9' moved 0,+72 pt — cause: inserted Other 'banner'"))
        #expect(lines.contains("  B/light: motion not compared: no shift record on reference"))
        #expect(!lines.contains { $0.contains("[light]") })
    }

    @Test
    func aScreenWhoseOnlyShiftResultIsANoteIsNotOnTheCleanLine() throws {
        let diff = try Self.diff(reference: nil, run: [Self.shift("Row 2")])

        #expect(diff.flagCount == 0)
        #expect(BundleDiffRendering.cleanLine(diff).isEmpty)
    }

    @Test
    func anAnonymousElementPrintsWhatHoldsItAndNotAsItsOwnLabel() {
        let anonymous = CaptureManifest.Motion.Element(type: "Cell", identifier: nil, label: nil, path: [0, 0], within: "Groceries")
        let named = CaptureManifest.Motion.Element(type: "Cell", identifier: nil, label: "Groceries", path: [0, 0])

        #expect(BundleDiffRendering.elementText(anonymous) == "Cell in 'Groceries'")
        #expect(BundleDiffRendering.elementText(named) == "Cell 'Groceries'")
        #expect(BundleDiffRendering.elementText(CaptureManifest.Motion.Element(type: "Cell", identifier: nil, label: nil, path: [0])) == "Cell")
    }

    @Test
    func anElementRecordedBeforeWithinDecodes() throws {
        let json = #"{"type":"Cell","path":[0,1],"label":"Row"}"#

        let element = try JSONDecoder().decode(CaptureManifest.Motion.Element.self, from: Data(json.utf8))

        #expect(element == CaptureManifest.Motion.Element(type: "Cell", identifier: nil, label: "Row", path: [0, 1]))
        #expect(element.within == nil)
    }

    @Test
    func anOlderDiffWithoutTheShiftFieldsDecodes() throws {
        let screen = ScreenDiff(id: "s", referenceOutcome: .captured, runOutcome: .captured, states: [], unpairedStates: [])
        let encoded = try JSONEncoder().encode(screen)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["shiftFlags"] = nil
        object["shiftNotes"] = nil

        let decoded = try JSONDecoder().decode(ScreenDiff.self, from: JSONSerialization.data(withJSONObject: object))

        #expect(decoded == screen)
        #expect(decoded.shiftFlags == nil)
    }

    private static func shift(
        _ label: String,
        dy: Double = 72,
        cause: CaptureManifest.Motion.Cause? = CaptureManifest.Motion.Cause(
            change: .inserted,
            element: CaptureManifest.Motion.Element(type: "Other", identifier: nil, label: "banner", path: [0, 0])
        ),
        path: [Int] = [0, 2],
        at milliseconds: Int = 300
    ) -> CaptureManifest.Motion.Shift {
        CaptureManifest.Motion.Shift(
            element: CaptureManifest.Motion.Element(type: "Button", identifier: nil, label: label, path: path),
            before: AXNode.Frame(x: 0, y: 100, width: 300, height: 44),
            after: AXNode.Frame(x: 0, y: 100 + dy, width: 300, height: 44),
            movedAtMilliseconds: milliseconds,
            cause: cause
        )
    }

    private static func motion(_ shifts: [CaptureManifest.Motion.Shift]?) -> CaptureManifest.Motion {
        CaptureManifest.Motion(settleMilliseconds: 100, readIntervalMilliseconds: 50, readCount: 4, shifts: shifts)
    }

    private static func diff(reference: [CaptureManifest.Motion.Shift]?, run: [CaptureManifest.Motion.Shift]?) throws -> BundleDiff {
        try diff(referenceMotion: reference.map { [motion($0)] } ?? [nil], runMotion: run.map { [motion($0)] } ?? [nil])
    }

    private static func diff(referenceMotion: [CaptureManifest.Motion?], runMotion: [CaptureManifest.Motion?]) throws -> BundleDiff {
        let (referenceDirectory, runDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let reference = try bundle(in: referenceDirectory, captures: [(light, referenceMotion[0])])
        let run = try bundle(in: runDirectory, captures: [(light, runMotion[0])])
        return BundleDiff.compare(run: run, against: reference)
    }

    private static func twoScreens(in directory: TemporaryDirectory, a: CaptureManifest.Motion?, b: CaptureManifest.Motion?) throws -> CaptureBundle {
        try CaptureBundleFixture.writeWalk(in: directory, screens: [("A", a), ("B", b)].map { id, motion in
            CaptureBundleFixture.ScreenSpec(id: id, captures: [CaptureBundleFixture.Capture(screenID: id, state: light, tree: CaptureBundleFixture.plainScreen(), motion: motion)])
        })
    }

    private static func bundle(in directory: TemporaryDirectory, captures: [(Walkbook.CaptureState, CaptureManifest.Motion?)]) throws -> CaptureBundle {
        try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "s", captures: captures.map { state, motion in
                CaptureBundleFixture.Capture(screenID: "s", state: state, tree: CaptureBundleFixture.plainScreen(), motion: motion)
            }),
        ])
    }
}
