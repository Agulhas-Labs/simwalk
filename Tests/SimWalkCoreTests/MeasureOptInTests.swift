//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// A screen's `measure` and the performance budgets that imply it (SimWalk#67, M4), and the one rule that keeps them apart from `motion`.
struct MeasureOptInTests {
    private static func json(_ screenFields: String) -> Data {
        Data(#"{"name":"w","appBundleID":"a","screens":[{"id":"about","route":[{"tab":{"label":"About"}}],"states":[{"theme":"light"}]\#(screenFields)}]}"#.utf8)
    }

    /// Loaded, so a walkbook with a problem is refused.
    private static func book(_ screenFields: String) throws -> Walkbook {
        try WalkbookLoader.load(from: json(screenFields), source: "test")
    }

    /// Decoded only, so the problems the loader would refuse can be read.
    private static func unvalidated(_ screenFields: String) throws -> Walkbook {
        try JSONDecoder().decode(Walkbook.self, from: json(screenFields))
    }

    private static func screen(measure: Walkbook.Measure? = nil, motion: Bool? = nil, budgets: Walkbook.Budgets? = nil) -> Walkbook.Screen {
        Walkbook.Screen(id: "about", route: [.tab(label: "About")], states: [Walkbook.CaptureState(theme: .light)], motion: motion, measure: measure, budgets: budgets)
    }

    @Test
    func measureIsTrueAnObjectOrOff() throws {
        #expect(try Self.book(#","measure":true"#).screens[0].measure == Walkbook.Measure(iterations: 3))
        #expect(try Self.book(#","measure":{"iterations":7}"#).screens[0].measure == Walkbook.Measure(iterations: 7))
        #expect(try Self.book(#","measure":{}"#).screens[0].measure == Walkbook.Measure(iterations: 3))
        #expect(try Self.book(#","measure":false"#).screens[0].measure == nil)
        #expect(try Self.book("").screens[0].measure == nil)
    }

    @Test
    func iterationsOutsideOneToTenAreAProblemNamingTheScreen() throws {
        for value in [0, 11, -1] {
            let book = try Self.unvalidated(#","measure":{"iterations":\#(value)}"#)

            #expect(WalkbookLoader.problems(in: book) == [.measureIterationsOutOfRange(screenID: "about", index: 0, value: value)])
        }

        #expect(try WalkbookLoader.problems(in: Self.book(#","measure":{"iterations":10}"#)).isEmpty)
        #expect(try WalkbookLoader.problems(in: Self.book(#","measure":{"iterations":1}"#)).isEmpty)
    }

    @Test
    func anUnknownKeyInMeasureIsRefused() {
        #expect(throws: (any Error).self) {
            try Self.book(#","measure":{"iteration":3}"#)
        }
    }

    @Test
    func aWalkbookWithoutMeasureHashesAsItAlwaysDidAndTheTwoSpellingsOfTheDefaultAreOne() throws {
        let bare = try Self.book("")

        let encoded = try String(decoding: JSONEncoder().encode(bare), as: UTF8.self)

        #expect(!encoded.contains("measure"))
        #expect(try WalkbookIdentity.hash(of: Self.book(#","measure":true"#)) == WalkbookIdentity.hash(of: Self.book(#","measure":{"iterations":3}"#)))
        #expect(try WalkbookIdentity.hash(of: Self.book(#","measure":true"#)) != WalkbookIdentity.hash(of: bare))
        #expect(try Self.book(#","measure":{"iterations":5}"#).screens[0].measure?.iterations == JSONDecoder().decode(Walkbook.self, from: JSONEncoder().encode(Self.book(#","measure":{"iterations":5}"#))).screens[0].measure?.iterations)
    }

    @Test
    func performanceBudgetsAreDecodedAndCheckedForEmptinessAndSign() throws {
        let book = try Self.book(#","budgets":{"launchMs":500,"transitionHitches":0,"cpuMs":2000,"memoryPeakMB":120}"#)

        #expect(book.screens[0].budgets == Walkbook.Budgets(launchMs: 500, transitionHitches: 0, cpuMs: 2000, memoryPeakMB: 120))
        #expect(WalkbookLoader.problems(in: book).isEmpty)
        #expect(try WalkbookLoader.problems(in: Self.unvalidated(#","budgets":{"cpuMs":-1}"#)) == [.negativeBudget(screenID: "about", index: 0, key: "cpuMs", value: -1)])
        #expect(try WalkbookLoader.problems(in: Self.unvalidated(#","budgets":{}"#)) == [.emptyBudgets(screenID: "about", index: 0)])
        #expect(throws: (any Error).self) { try Self.book(#","budgets":{"launchMilliseconds":1}"#) }
    }

    /// G2: a performance budget implies `measure` and not `motion`; a motion budget implies `motion` and not `measure`.
    @Test
    func performanceBudgetsImplyMeasureButNotMotion() {
        let screen = Self.screen(budgets: Walkbook.Budgets(launchMs: 500))

        #expect(MeasureOptIn.iterations(for: screen) == 3)
        #expect(!MotionOptIn.records(screen, in: [:]))
    }

    @Test
    func motionBudgetsImplyMotionButNotMeasure() {
        let screen = Self.screen(budgets: Walkbook.Budgets(settleMs: 500))

        #expect(MotionOptIn.records(screen, in: [:]))
        #expect(MeasureOptIn.iterations(for: screen) == nil)
        #expect(MotionOptIn.records(Self.screen(budgets: Walkbook.Budgets(layoutShifts: 0)), in: [:]))
    }

    @Test
    func aMixedBudgetImpliesBothAndAStatedMeasureKeepsItsIterations() {
        let both = Self.screen(budgets: Walkbook.Budgets(settleMs: 500, cpuMs: 100))

        #expect(MotionOptIn.records(both, in: [:]))
        #expect(MeasureOptIn.iterations(for: both) == 3)
        #expect(MeasureOptIn.iterations(for: Self.screen(measure: Walkbook.Measure(iterations: 5), budgets: Walkbook.Budgets(cpuMs: 100))) == 5)
        #expect(MeasureOptIn.iterations(for: Self.screen(measure: Walkbook.Measure(iterations: 1))) == 1)
        #expect(MeasureOptIn.iterations(for: Self.screen(motion: true)) == nil)
    }

    /// What a simulator walk adds to its answer: the measured screens it executes, so `--screens` leaving them out leaves the note out.
    @Test
    func aSimulatorWalkNoteNamesTheMeasuredScreenItWalksAndHonoursScreens() throws {
        let measured = try Self.book(#","measure":true"#)

        #expect(MeasureOptIn.walkNote(for: measured, screens: []) == "measure: device only, not run (about)")
        #expect(MeasureOptIn.walkNote(for: measured, screens: ["about"]) == "measure: device only, not run (about)")
        #expect(MeasureOptIn.walkNote(for: measured, screens: ["elsewhere"]) == nil)
        #expect(try MeasureOptIn.walkNote(for: Self.book(""), screens: []) == nil)
    }

    @Test
    func theDeviceOnlyNoteNamesTheMeasuredScreensAndIsAbsentWithoutAny() throws {
        let measured = try Self.book(#","measure":true"#)

        #expect(MeasureOptIn.deviceOnlyNote(for: measured.screens) == "measure: device only, not run (about)")
        #expect(try MeasureOptIn.deviceOnlyNote(for: Self.book("").screens) == nil)
        #expect(try WalkbookSummary(measured).answer().text.contains("measure: device only, not run (about)"))
        #expect(try !WalkbookSummary(Self.book("")).answer().text.contains("measure:"))
    }

    /// `validate --device` applies the device rules, under which a measured screen is measured, so "device only, not run" would be false there.
    @Test
    func aDeviceValidationLeavesTheDeviceOnlyNoteOut() throws {
        let measured = try Self.book(#","measure":true"#)

        #expect(try !WalkbookSummary(measured, onDevice: true).answer().text.contains("measure:"))
    }

    private static func measuring(_ count: Int) -> Walkbook {
        let screens = (0 ..< count).map { index in
            Walkbook.Screen(id: "s\(index)", route: [.tab(label: "About")], states: [Walkbook.CaptureState(theme: .light)], measure: Walkbook.Measure(iterations: 3))
        }
        return Walkbook(name: "w", appBundleID: "a", screens: screens)
    }

    @Test
    func moreThanTwentyMeasuredScreenStatesNoteTheLaunchEnvironmentAndTwentyDoNot() {
        #expect(MeasureOptIn.launchEnvironmentNote(for: Self.measuring(20)) == nil)
        #expect(MeasureOptIn.launchEnvironmentNote(for: Self.measuring(21)) == "measure: 21 screen-states — each adds about 3 KB to the runner's launch environment; above about 50 the walk's runner may fail to launch")
    }

    @Test
    func validateNotesALargeMeasuredWalkbook() throws {
        let note = try #require(MeasureOptIn.launchEnvironmentNote(for: Self.measuring(21)))
        let answer = try WalkbookSummary(Self.measuring(21)).answer()

        #expect(answer.residue.contains(note))
        #expect(try !WalkbookSummary(Self.measuring(20)).answer().residue.contains { $0.contains("launch environment") })
    }
}
