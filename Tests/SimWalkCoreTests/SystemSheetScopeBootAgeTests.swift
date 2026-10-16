//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// A `systemTap` that saw no sheet on a freshly booted device names the boot, not an answered sheet (SimWalk#88): HealthKit raises none on a simulator for its first minutes, and erasing the device restarts the wait.
struct SystemSheetScopeBootAgeTests {
    private static let screen = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)
    private static let allow = AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 700, width: 361, height: 50), label: "Allow", identifier: "UIA.Health.Allow.Button")
    private static var answered: String {
        "a sheet already answered is not asked again"
    }

    /// The plain refusal on a device booted 70 s ago names the age, rounded to whole seconds, and says to wait on the same device.
    @Test
    func aFreshBootNamesItsAgeInPlaceOfAnAnsweredSheet() {
        let refusal = SystemSheetScope(baseline: Self.window([])).refusal(for: "Allow", passedOverAppOwn: false, bootAge: 70.4)

        #expect(refusal.contains("the device booted 70 s ago"))
        #expect(refusal.contains("wait and walk again on the same device"))
        #expect(!refusal.contains(Self.answered))
    }

    /// A step declared `atLaunch` that saw nothing on a fresh boot names the boot too.
    @Test
    func aFreshBootNamesItsAgeForAStepDeclaredAtLaunch() {
        let refusal = SystemSheetScope.admittingAll(of: Self.window([])).refusal(for: "Allow", passedOverAppOwn: false, bootAge: 12)

        #expect(refusal.contains("which the walkbook declares a system sheet's"))
        #expect(refusal.contains("the device booted 12 s ago"))
        #expect(!refusal.contains(Self.answered))
    }

    /// **An `atLaunch` step's tree cannot tell a sheet from none** (SimWalk#90 item 4): a fresh boot with the sheet up and the label mistyped looks the same as no sheet, so the refusal says the tree cannot tell, and asks for the label to be checked.
    @Test
    func aFreshBootForAStepDeclaredAtLaunchDoesNotClaimTheAppsWindowShowedNoSheet() {
        let refusal = SystemSheetScope.admittingAll(of: Self.window([])).refusal(for: "Allow", passedOverAppOwn: false, bootAge: 12)

        #expect(refusal.contains("the tree cannot say whether one showed in the app's window at launch"))
        #expect(refusal.contains("check it"))
        #expect(!refusal.contains("neither SpringBoard nor the app's window showed one"))
        #expect(refusal.contains("wait and walk again on the same device"))
    }

    /// A step not declared `atLaunch` keeps its wording on a fresh boot: its baseline is the app's screen, so a sheet would be new and none seen is none showed.
    @Test
    func aFreshBootForAStepNotDeclaredAtLaunchKeepsItsWording() {
        let refusal = SystemSheetScope(baseline: Self.window([])).refusal(for: "Allow", passedOverAppOwn: false, bootAge: 12)

        #expect(refusal.contains("neither SpringBoard nor a sheet in the app's window showed one"))
        #expect(!refusal.contains("check it"))
    }

    /// An `atLaunch` step on a device past ``SystemSheetScope/freshBoot`` keeps the answered-sheet hint, with the honest wording about the app's window (SimWalk#91).
    @Test
    func anOldBootForAStepDeclaredAtLaunchKeepsItsHint() {
        let refusal = SystemSheetScope.admittingAll(of: Self.window([])).refusal(for: "Allow", passedOverAppOwn: false, bootAge: 3600)

        #expect(refusal.contains("the tree cannot say whether one showed in the app's window at launch"))
        #expect(refusal.hasSuffix(Self.answered))
    }

    /// From ``SystemSheetScope/freshBoot`` on, the answered sheet is the likelier reading again.
    @Test
    func aDeviceBootedLongerAgoKeepsTheAnsweredSheet() {
        let scope = SystemSheetScope(baseline: Self.window([]))

        #expect(scope.refusal(for: "Allow", passedOverAppOwn: false, bootAge: SystemSheetScope.freshBoot).hasSuffix(Self.answered))
        #expect(scope.refusal(for: "Allow", passedOverAppOwn: false, bootAge: 3600).hasSuffix(Self.answered))
    }

    /// A boot time the host could not read keeps the answered sheet.
    @Test
    func anUnknownBootKeepsTheAnsweredSheet() {
        let refusal = SystemSheetScope(baseline: Self.window([])).refusal(for: "Allow", passedOverAppOwn: false, bootAge: nil)

        #expect(refusal.hasSuffix(Self.answered))
        #expect(!refusal.contains("booted"))
    }

    /// The ambiguous refusal saw a match, so the boot explains nothing there and its text is what it was with no age at all.
    @Test
    func anAmbiguousRefusalIsUnchangedOnAFreshBoot() {
        let scope = SystemSheetScope(baseline: Self.window([Self.allow]))
        let fresh = scope.refusal(for: "Allow", passedOverAppOwn: true, bootAge: 70)

        #expect(fresh.contains("ambiguous"))
        #expect(fresh == scope.refusal(for: "Allow", passedOverAppOwn: true, bootAge: nil))
    }

    /// A control live on screen that the snapshot cannot see is refused as the snapshot's blindness, fresh boot or not.
    @Test
    func aSnapshotBlindRefusalIsUnchangedOnAFreshBoot() {
        let home = Self.window([])
        var search = SystemTapSearch(label: "Allow", scope: SystemSheetScope(baseline: home))
        let found: Int? = search.poll(home, springBoardShowedSheet: false) { accepts in accepts(Self.allow) ? 1 : nil }
        let fresh = search.refusal(bootAge: 70)

        #expect(found == nil)
        #expect(fresh.cause == .snapshotBlind)
        #expect(fresh.reason == search.refusal(bootAge: nil).reason)
        #expect(!fresh.reason.contains("booted 70 s"))
    }

    /// **A sheet that was up whose control the label missed is not one HealthKit failed to raise** (SimWalk#88 review): the poll saw a subtree the baseline lacked, so the refusal keeps the answered-sheet wording on a fresh boot.
    @Test
    func aSheetSeenWithoutTheLabelKeepsTheAnsweredSheetOnAFreshBoot() {
        let other = AXNode(type: "Button", frame: Self.allow.frame, label: "Deny", identifier: "UIA.Health.Deny.Button")
        let sheetUp = Self.window([AXNode(type: "Other", frame: Self.screen, identifier: "UIA.Health.AuthSheet", children: [other])])
        var search = SystemTapSearch(label: "Allow", scope: SystemSheetScope(baseline: Self.window([])))

        let found: Int? = search.poll(sheetUp, springBoardShowedSheet: false) { _ in nil }
        let reason = search.refusal(bootAge: 70).reason

        #expect(found == nil)
        #expect(reason.hasSuffix(Self.answered))
        #expect(!reason.contains("booted"))
    }

    /// No new subtree in any poll is no sheet seen: the fresh boot is named.
    @Test
    func aSearchThatSawNoSheetNamesTheFreshBoot() {
        let home = Self.window([])
        var search = SystemTapSearch(label: "Allow", scope: SystemSheetScope(baseline: home))

        let found: Int? = search.poll(home, springBoardShowedSheet: false) { _ in nil }

        #expect(found == nil)
        #expect(search.refusal(bootAge: 70).reason.contains("the device booted 70 s ago"))
    }

    /// A SpringBoard sheet the runner reports, though it held no matching control, is a sheet seen.
    @Test
    func aSpringBoardSheetSeenKeepsTheAnsweredSheetOnAFreshBoot() {
        let home = Self.window([])
        var search = SystemTapSearch(label: "Allow", scope: SystemSheetScope(baseline: home))

        let found: Int? = search.poll(home, springBoardShowedSheet: true) { _ in nil }
        let reason = search.refusal(bootAge: 70).reason

        #expect(found == nil)
        #expect(reason.hasSuffix(Self.answered))
        #expect(!reason.contains("booted"))
    }

    /// An `atLaunch` refusal off a fresh boot never claims the app's window showed no sheet: `showsSheet(in:)` is always false for it, so the tree cannot back that (SimWalk#91).
    ///
    /// Where the boot is old, or its age unknown, it says what the fresh-boot wording says and keeps the answered-sheet hint.
    @Test(arguments: [3600, nil] as [TimeInterval?])
    func anAtLaunchRefusalOffAFreshBootDoesNotClaimTheAppWindowShowedNone(bootAge: TimeInterval?) {
        let refusal = SystemSheetScope.admittingAll(of: Self.window([])).refusal(for: "Allow", passedOverAppOwn: false, bootAge: bootAge)

        #expect(refusal.contains("SpringBoard showed no alert SimWalk could read, and the tree cannot say whether one showed in the app's window at launch"))
        #expect(!refusal.contains("neither SpringBoard nor"))
        #expect(refusal.hasSuffix(Self.answered))
    }

    /// Where SpringBoard showed an alert without the label, the refusal says so rather than that it showed none, in an `atLaunch` step and in the plain one (SimWalk#91).
    ///
    /// The boot age is dropped too: a device that raised an alert is not one that raised nothing.
    @Test
    func anAlertSpringBoardShowedIsNotReportedAsNone() {
        let atLaunch = SystemSheetScope.admittingAll(of: Self.window([])).refusal(for: "Allow", passedOverAppOwn: false, bootAge: 12, springBoardShowedAlert: true)
        let plain = SystemSheetScope(baseline: Self.window([])).refusal(for: "Allow", passedOverAppOwn: false, bootAge: 12, springBoardShowedAlert: true)

        #expect(atLaunch.contains("SpringBoard showed an alert with no enabled 'Allow', and the tree cannot say whether one showed in the app's window at launch"))
        #expect(plain.contains("SpringBoard showed an alert with no enabled 'Allow', and no sheet in the app's window held one"))
        for refusal in [atLaunch, plain] {
            #expect(!refusal.contains("SpringBoard showed no alert SimWalk could read"))
            #expect(!refusal.contains("neither SpringBoard nor"))
            #expect(!refusal.contains("booted"))
            #expect(refusal.hasSuffix(Self.answered))
        }
    }

    /// The search carries the alert through to the refusal's wording, not only the boot age (SimWalk#91).
    @Test
    func aSearchThatSawASpringBoardAlertSaysSo() {
        let home = Self.window([])
        var search = SystemTapSearch(label: "Allow", scope: SystemSheetScope(baseline: home))

        let found: Int? = search.poll(home, springBoardShowedSheet: true) { _ in nil }

        #expect(found == nil)
        #expect(search.refusal(bootAge: 70).reason.contains("SpringBoard showed an alert with no enabled 'Allow'"))
    }

    /// A step declared `atLaunch` has every subtree new, which says nothing of a sheet: the fresh boot is still named.
    @Test
    func aStepDeclaredAtLaunchIsNotTakenToHaveSeenASheetByItsTree() {
        let home = Self.window([])
        var search = SystemTapSearch(label: "Allow", scope: .admittingAll(of: home))

        let found: Int? = search.poll(home, springBoardShowedSheet: false) { _ in nil }

        #expect(found == nil)
        #expect(search.refusal(bootAge: 12).reason.contains("the device booted 12 s ago"))
    }

    private static func window(_ content: [AXNode]) -> AXNode {
        AXNode(type: "Application", frame: screen, label: "RouteFixture", children: [AXNode(type: "Window", frame: screen, children: content)])
    }
}
