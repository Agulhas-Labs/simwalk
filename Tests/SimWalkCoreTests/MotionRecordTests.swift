//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// The `motion` record a capture files when asked (SimWalk#67): absent means "motion not recorded", it stays inside format 8, and a walkbook asks for it per screen or a walk for every screen.
struct MotionRecordTests {
    /// A capture with the record reads back as written, and one without it writes no `motion` key at all — absent, never `null`, so a capture that recorded nothing cannot be read as one that recorded no motion.
    @Test
    func aCaptureRoundTripsWithAndWithoutMotionAndWritesNoKeyWithout() throws {
        let motion = CaptureManifest.Motion(settleMilliseconds: 500, readIntervalMilliseconds: 250, readCount: 4)
        let recorded = CaptureManifest.StateCapture(screenID: "today", state: Walkbook.CaptureState(theme: .light), axTreeSettled: true, motion: motion)
        let bare = CaptureManifest.StateCapture(screenID: "today", state: Walkbook.CaptureState(theme: .light), axTreeSettled: true)

        #expect(try JSONDecoder().decode(CaptureManifest.StateCapture.self, from: JSONEncoder().encode(recorded)) == recorded)
        #expect(try JSONDecoder().decode(CaptureManifest.StateCapture.self, from: JSONEncoder().encode(bare)) == bare)
        #expect(try !String(decoding: JSONEncoder().encode(bare), as: UTF8.self).contains("motion"))
    }

    /// An unsettled watch's record keeps its cadence and reads and writes no settle time.
    @Test
    func anUnsettledRecordWritesNoSettleTime() throws {
        let unsettled = CaptureManifest.Motion(settleMilliseconds: nil, readIntervalMilliseconds: 250, readCount: 11)

        let written = try String(decoding: JSONEncoder().encode(unsettled), as: UTF8.self)

        #expect(!written.contains("settleMilliseconds"))
        #expect(written.contains("\"readCount\":11"))
    }

    /// **No format bump**: a format-8 manifest carrying `motion` reads, and a capture decodes leniently — a key this build has never heard of is ignored, which is what lets a format-8 reader that predates `motion` read a bundle carrying it and lose only the record.
    @Test
    func aFormatEightManifestCarryingMotionReadsAndUnknownCaptureKeysAreIgnored() throws {
        let capture = #"{"state":{"theme":"light"},"screenshotPath":"screens/today/light/screen.png","axTreePath":"screens/today/light/ax-tree.json","axTreeSettled":true,"#
        let json = #"{"formatVersion":8,"walkName":"w","appBundleID":"a","appBuildHash":"h","walkbookHash":"wh","device":{"name":"d","udid":"u","osVersion":"26.0"},"startedAt":0,"finishedAt":1,"settleQuietMilliseconds":250,"screens":[{"id":"today","outcome":{"captured":{}},"routeTaken":[],"captures":["#
            + capture + #""motion":{"settleMilliseconds":500,"readIntervalMilliseconds":250,"readCount":4}},"#
            + capture + #""fromALaterBuild":{"anything":1}}]}]}"#

        let manifest = try JSONDecoder().decode(CaptureManifest.self, from: Data(json.utf8))

        #expect(manifest.formatVersion == CaptureManifest.currentFormatVersion)
        #expect(manifest.screens[0].captures[0].motion == CaptureManifest.Motion(settleMilliseconds: 500, readIntervalMilliseconds: 250, readCount: 4))
        #expect(manifest.screens[0].captures[1].motion == nil)
    }

    /// **M2 stays inside format 8** (G3): an M1 record — no spacing, landing or shifts — still decodes, reading its shifts as not recorded rather than as none; an M2 record with them round-trips, an empty shift list included, which is written and so stays distinct from absent; and a capture without `motion` reads as not recorded.
    @Test
    func anM1RecordAndAnM2RecordBothDecodeAndAbsentShiftsAreNotRecorded() throws {
        let earlier = try JSONDecoder().decode(CaptureManifest.Motion.self, from: Data(#"{"settleMilliseconds":500,"readIntervalMilliseconds":250,"readCount":4}"#.utf8))
        let element = CaptureManifest.Motion.Element(type: "StaticText", identifier: nil, label: "Row 1", path: [0, 0, 1])
        let shift = CaptureManifest.Motion.Shift(
            element: element,
            before: AXNode.Frame(x: 16, y: 100, width: 370, height: 44),
            after: AXNode.Frame(x: 16, y: 168, width: 370, height: 44),
            movedAtMilliseconds: 1200,
            cause: CaptureManifest.Motion.Cause(change: .inserted, element: CaptureManifest.Motion.Element(type: "StaticText", identifier: "banner", label: "Banner", path: [0, 0, 0]))
        )
        let later = CaptureManifest.Motion(settleMilliseconds: 1250, readIntervalMilliseconds: 100, readCount: 16, measuredReadSpacingMilliseconds: 118, landingMilliseconds: 40, shifts: [shift])
        let still = CaptureManifest.Motion(settleMilliseconds: 120, readIntervalMilliseconds: 100, readCount: 4, measuredReadSpacingMilliseconds: 110, shifts: [])
        let bare = try JSONDecoder().decode(CaptureManifest.StateCapture.self, from: Data(#"{"state":{"theme":"light"},"screenshotPath":"s.png","axTreePath":"a.json"}"#.utf8))

        #expect(earlier == CaptureManifest.Motion(settleMilliseconds: 500, readIntervalMilliseconds: 250, readCount: 4))
        #expect(earlier.shifts == nil)
        #expect(earlier.measuredReadSpacingMilliseconds == nil)
        #expect(earlier.landingMilliseconds == nil)
        #expect(try JSONDecoder().decode(CaptureManifest.Motion.self, from: JSONEncoder().encode(later)) == later)
        #expect(try JSONDecoder().decode(CaptureManifest.Motion.self, from: JSONEncoder().encode(still)).shifts == [])
        #expect(try String(decoding: JSONEncoder().encode(still), as: UTF8.self).contains(#""shifts":[]"#))
        #expect(bare.motion == nil)
    }

    /// The route's last step tells the watch whether a scroll was asked for: a `scrollTo` or a `systemTap`, never a navigating step or no route.
    @Test
    func onlyAScrollToOrASystemTapLeavesTheWatchAfterAScroll() {
        let steps: [Walkbook.RouteStep?] = [.scrollTo(label: "Row"), .systemTap(label: "Allow", atLaunch: false, owner: nil), .tap(label: "Row"), .openURL(url: "x://y"), nil]

        #expect(steps.map { MotionWatch(lastStep: $0, landing: nil).afterScroll } == [true, true, false, false, false])
    }

    /// A screen's `"motion": true` decodes, and a walkbook without it writes no `motion` key, so every walkbook already on disk hashes as it did.
    @Test
    func aScreensMotionDecodesAndIsLeftOutWhenAbsent() throws {
        let screen = try JSONDecoder().decode(Walkbook.Screen.self, from: Data(#"{"id":"today","route":[],"states":[{"theme":"light"}],"motion":true}"#.utf8))
        let plain = Walkbook.Screen(id: "today", route: [], states: [Walkbook.CaptureState(theme: .light)])

        #expect(screen.motion == true)
        #expect(try !String(decoding: JSONEncoder().encode(plain), as: UTF8.self).contains("motion"))
    }

    /// A `motion` that is not a Boolean is refused rather than read as off: `"yes"` is someone asking for it.
    @Test
    func aMotionThatIsNotABooleanIsRefused() throws {
        func book(motion: String) -> Data {
            Data(#"{"name":"w","appBundleID":"a","screens":[{"id":"today","route":[{"tab":{"label":"Today"}}],"states":[{"theme":"light"}],"motion":\#(motion)}]}"#.utf8)
        }

        #expect(try WalkbookLoader.load(from: book(motion: "true"), source: "book.json").screens[0].motion == true)
        #expect(throws: WalkbookLoadError.self) {
            try WalkbookLoader.load(from: book(motion: #""yes""#), source: "book.json")
        }
    }

    /// `--motion` asks for every screen, a screen's own `true` for that screen alone, and neither for none — `false` on a screen does not outvote the flag.
    @Test
    func theWalksFlagRecordsEveryScreenAndAScreenOnlyItself() {
        let asking = Walkbook.Screen(id: "a", route: [], states: [Walkbook.CaptureState(theme: .light)], motion: true)
        let declining = Walkbook.Screen(id: "b", route: [], states: [Walkbook.CaptureState(theme: .light)], motion: false)
        let silent = Walkbook.Screen(id: "c", route: [], states: [Walkbook.CaptureState(theme: .light)])
        let flagged = [MotionOptIn.environmentKey: MotionOptIn.walkWideValue]

        #expect([asking, declining, silent].map { MotionOptIn.records($0, in: flagged) } == [true, true, true])
        #expect([asking, declining, silent].map { MotionOptIn.records($0, in: [:]) } == [true, false, false])
    }

    /// A budget asks for the motion it is checked against: a screen with budgets records without `"motion": true` and without `--motion`.
    @Test
    func aScreenWithBudgetsRecordsMotionWithoutAskingForIt() {
        let budgeted = Walkbook.Screen(id: "a", route: [], states: [Walkbook.CaptureState(theme: .light)], budgets: Walkbook.Budgets(settleMs: 1500))
        let silent = Walkbook.Screen(id: "b", route: [], states: [Walkbook.CaptureState(theme: .light)])

        #expect(MotionOptIn.records(budgeted, in: [:]))
        #expect(!MotionOptIn.records(silent, in: [:]))
    }
}
