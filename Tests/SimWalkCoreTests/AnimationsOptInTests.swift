//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// Whether a simulator walk launches the app with UIKit animations off, and how the library reaches it (SimWalk#154).
struct AnimationsOptInTests {
    @Test
    func theKeysAreNamedLiterally() {
        #expect(AnimationsOptIn.environmentKey == "SIMWALK_ANIMATIONS_OFF_LIBRARY")
        #expect(AnimationsOptIn.hostEnvironmentKey == "TEST_RUNNER_SIMWALK_ANIMATIONS_OFF_LIBRARY")
    }

    @Test
    func theLibraryIsReadOnlyWhenSetAndNonEmpty() {
        #expect(AnimationsOptIn.library(in: [:]) == nil)
        #expect(AnimationsOptIn.library(in: [AnimationsOptIn.environmentKey: ""]) == nil)
        #expect(AnimationsOptIn.library(in: [AnimationsOptIn.environmentKey: "/lib.dylib"]) == "/lib.dylib")
    }

    @Test
    func theManifestRecordsOffOnlyWhenTheLibraryIsPresent() {
        #expect(AnimationsOptIn.recorded(in: [AnimationsOptIn.environmentKey: "/lib.dylib"]) == .disabled)
        #expect(AnimationsOptIn.recorded(in: [:]) == .enabled)
        #expect(AnimationsOptIn.recorded(in: [AnimationsOptIn.environmentKey: ""]) == .enabled)
    }

    @Test
    func insertingNothingChangesNothing() {
        #expect(AnimationsOptIn.inserting(nil, into: ["A": "1"]) == ["A": "1"])
    }

    @Test
    func aLibraryIsInsertedAloneOrAfterAnExistingOne() {
        #expect(AnimationsOptIn.inserting("/lib", into: ["A": "1"]) == ["A": "1", "DYLD_INSERT_LIBRARIES": "/lib"])
        #expect(AnimationsOptIn.inserting("/lib", into: ["DYLD_INSERT_LIBRARIES": ""]) == ["DYLD_INSERT_LIBRARIES": "/lib"])
        #expect(AnimationsOptIn.inserting("/lib", into: ["DYLD_INSERT_LIBRARIES": "/other"]) == ["DYLD_INSERT_LIBRARIES": "/other:/lib"])
    }

    @Test
    func aPlainWalkTurnsAnimationsOff() {
        #expect(AnimationsOptIn.decision(for: Self.book([Self.screen("a")]), screens: [], animations: false, motion: false) == .off)
    }

    @Test
    func askingKeepsThemOnAndWinsOverMotion() {
        let plain = Self.book([Self.screen("a")])

        #expect(AnimationsOptIn.decision(for: plain, screens: [], animations: true, motion: false) == .keptOn(.asked))
        #expect(AnimationsOptIn.decision(for: plain, screens: [], animations: true, motion: true) == .keptOn(.asked))
    }

    @Test
    func aWalkWideMotionKeepsThemOn() {
        #expect(AnimationsOptIn.decision(for: Self.book([Self.screen("a")]), screens: [], animations: false, motion: true) == .keptOn(.motion))
    }

    @Test
    func aMotionScreenKeepsThemOn() {
        let moving = Self.book([Self.screen("a"), Self.screen("b", motion: true)])

        #expect(AnimationsOptIn.decision(for: moving, screens: [], animations: false, motion: false) == .keptOn(.motion))
    }

    @Test
    func aMotionBudgetKeepsThemOn() {
        let budgeted = Self.book([Self.screen("a", budgets: Walkbook.Budgets(settleMs: 500))])

        #expect(AnimationsOptIn.decision(for: budgeted, screens: [], animations: false, motion: false) == .keptOn(.motion))
    }

    @Test
    func aPerformanceOnlyBudgetDoesNotKeepThemOn() {
        let budgeted = Self.book([Self.screen("a", budgets: Walkbook.Budgets(cpuMs: 500))])

        #expect(AnimationsOptIn.decision(for: budgeted, screens: [], animations: false, motion: false) == .off)
    }

    @Test
    func aMotionScreenOutsideTheSelectionDoesNotKeepThemOn() {
        let mixed = Self.book([Self.screen("plain"), Self.screen("moving", motion: true)])

        #expect(AnimationsOptIn.decision(for: mixed, screens: ["plain"], animations: false, motion: false) == .off)
        #expect(AnimationsOptIn.decision(for: mixed, screens: ["moving"], animations: false, motion: false) == .keptOn(.motion))
    }

    private static func screen(_ id: String, motion: Bool? = nil, budgets: Walkbook.Budgets? = nil) -> Walkbook.Screen {
        Walkbook.Screen(id: id, route: [.tab(label: id)], states: [Walkbook.CaptureState(theme: .light)], motion: motion, budgets: budgets)
    }

    private static func book(_ screens: [Walkbook.Screen]) -> Walkbook {
        Walkbook(name: "w", appBundleID: "a", screens: screens)
    }
}
