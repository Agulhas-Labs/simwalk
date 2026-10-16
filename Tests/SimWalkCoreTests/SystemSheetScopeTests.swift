//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// A `systemTap` answers only a control in a subtree the app's own screen did not have, so the app's own `Continue` is never recorded as a system sheet's (SimWalk#28 review, items 1 and 2).
struct SystemSheetScopeTests {
    private static let screen = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)
    private static let continueFrame = AXNode.Frame(x: 20, y: 780, width: 362, height: 50)

    /// The app's own onboarding screen: a list of its own and a `Continue` button, nothing the system drew.
    private static func onboarding(continueAt frame: AXNode.Frame = continueFrame, heading: String = "Welcome") -> AXNode {
        AXNode(type: "Application", frame: screen, label: "App", children: [
            AXNode(type: "Window", frame: screen, children: [
                AXNode(type: "Other", frame: screen, identifier: "onboarding", children: [
                    AXNode(type: "StaticText", frame: screen, label: heading),
                    AXNode(type: "Table", frame: screen, children: [AXNode(type: "Cell", frame: screen, label: "Step one")]),
                    AXNode(type: "Button", frame: frame, label: "Continue"),
                ]),
            ]),
        ])
    }

    /// The same screen with a sheet hosted in the app's window over it, as HealthKit's is: its own list, and a `Continue` of its own unless it has gone.
    private static func onboardingUnderSheet(continueGone: Bool = false) -> AXNode {
        var tree = onboarding()
        let sheetContinue = AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: 600, width: 362, height: 50), label: "Continue", identifier: "UIA.Health.Allow.Button")
        tree.children[0].children.append(
            AXNode(type: "Other", frame: screen, children: [
                AXNode(type: "NavigationBar", frame: screen, identifier: "UIA.Health.AuthSheet", children: [
                    AXNode(type: "CollectionView", frame: AXNode.Frame(x: 0, y: 100, width: 402, height: 700), children: continueGone ? [] : [sheetContinue]),
                ]),
            ])
        )
        return tree
    }

    /// The negative gate: on a device that has already answered, the app's own `Continue` is all there is, and it is not admitted — even after its frame moved and its text changed with the data.
    @Test
    func theAppsOwnControlIsNeverAdmittedAsASheets() {
        let scope = SystemSheetScope(baseline: Self.onboarding())
        let moved = AXNode.Frame(x: 20, y: 700, width: 362, height: 50)
        let later = Self.onboarding(continueAt: moved, heading: "Welcome back")

        #expect(!scope.admits(AXNode(type: "Button", frame: Self.continueFrame, label: "Continue"), in: Self.onboarding()))
        #expect(!scope.admits(AXNode(type: "Button", frame: moved, label: "Continue"), in: later))
        #expect(scope.newSubtrees(of: later).isEmpty)
    }

    /// A sheet that arrived after the baseline is admitted, and the app's own `Continue` beneath it still is not.
    @Test
    func aControlInASubtreeThatAppearedIsAdmitted() {
        let scope = SystemSheetScope(baseline: Self.onboarding())
        let current = Self.onboardingUnderSheet()
        let sheetContinue = AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: 600, width: 362, height: 50), label: "Continue", identifier: "UIA.Health.Allow.Button")

        #expect(scope.admits(sheetContinue, in: current))
        #expect(!scope.admits(AXNode(type: "Button", frame: Self.continueFrame, label: "Continue"), in: current))
        #expect(scope.newSubtrees(of: current).map(\.children.first?.identifier) == ["UIA.Health.AuthSheet"])
    }

    /// A remote sheet's snapshot frames are in its own coordinate space, so its control is found by what it is, not where the snapshot puts it — and where the app's own screen holds the same control, only a frame that is the sheet's and not the app's admits it.
    @Test
    func aSheetsControlIsFoundByWhatItIsAndAFrameOnlyBreaksATie() {
        let scope = SystemSheetScope(baseline: Self.onboarding())
        var current = Self.onboarding()
        let sheetFrame = AXNode.Frame(x: 20, y: 600, width: 362, height: 50)
        current.children[0].children.append(AXNode(type: "Other", frame: Self.screen, children: [
            AXNode(type: "Button", frame: sheetFrame, label: "Continue"),
        ]))

        #expect(scope.admits(AXNode(type: "Button", frame: sheetFrame, label: "Continue"), in: current))
        #expect(!scope.admits(AXNode(type: "Button", frame: Self.continueFrame, label: "Continue"), in: current))
        #expect(!scope.admits(AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: 662, width: 362, height: 50), label: "Continue"), in: current))
        #expect(scope.admits(AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: 662, width: 362, height: 50), label: "Continue", identifier: "UIA.Health.Allow.Button"), in: Self.onboardingUnderSheet()))
    }

    /// An element the tree read beside it does not hold is not admitted: the next poll reads both again.
    @Test
    func anElementTheTreeDoesNotHoldIsNotAdmitted() {
        let scope = SystemSheetScope(baseline: Self.onboarding())

        #expect(!scope.admits(AXNode(type: "Button", frame: Self.screen, label: "Allow"), in: Self.onboardingUnderSheet()))
    }

    /// The scroll pass drags only a container a sheet brought — never the app's own list, before the sheet is up or under it.
    @Test
    func onlyASheetsOwnScrollContainerIsScrolled() throws {
        let scope = SystemSheetScope(baseline: Self.onboarding())

        #expect(scope.scrollContainer(in: Self.onboarding()) == nil)
        let target = try #require(scope.scrollContainer(in: Self.onboardingUnderSheet()))
        #expect(target.node.type == "CollectionView")
        #expect(target.node.frame.y == 100)
        #expect(target.path == "Application/Window/Other/NavigationBar#UIA.Health.AuthSheet/CollectionView")
    }

    /// A sheet already up when the app's screen is first read after launch is in the baseline, so none of it is admitted or scrolled — and the step says it is ambiguous rather than that no sheet showed, keeping the hint that a sheet already answered is not asked again (SimWalk#39 item 2).
    @Test
    func aSheetAlreadyUpAtTheReadIsNamedAmbiguous() {
        let scope = SystemSheetScope(baseline: Self.onboardingUnderSheet())
        let sheetContinue = AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: 600, width: 362, height: 50), label: "Continue", identifier: "UIA.Health.Allow.Button")

        #expect(!scope.admits(sheetContinue, in: Self.onboardingUnderSheet()))
        #expect(scope.scrollContainer(in: Self.onboardingUnderSheet()) == nil)
        let refusal = scope.refusal(for: "UIA.Health.Allow.Button", passedOverAppOwn: false)
        #expect(refusal.contains("ambiguous"))
        #expect(refusal.contains("a sheet already answered is not asked again"))
    }

    /// Where the baseline held no match, the refusal is the plain one: no sheet showed the control, and one already answered is not asked again.
    @Test
    func aLabelTheBaselineDidNotHoldIsRefusedPlainly() {
        let scope = SystemSheetScope(baseline: Self.onboarding())
        let refusal = scope.refusal(for: "Allow", passedOverAppOwn: false)

        #expect(!refusal.contains("ambiguous"))
        #expect(refusal.contains("a sheet already answered is not asked again"))
    }

    /// A step declared `atLaunch` that finds nothing names the declaration: nothing of the launch's screen was taken for the app's own, so a match there is not "present when the app's screen was last read" (SimWalk#46).
    @Test
    func aStepDeclaredAtLaunchIsRefusedNamingTheDeclaration() {
        let scope = SystemSheetScope.admittingAll(of: Self.onboarding())

        #expect(scope.refusal(for: "Continue", passedOverAppOwn: true) == "no enabled control 'Continue' on the launch's screen, which the walkbook declares a system sheet's — SpringBoard showed no alert SimWalk could read, and the tree cannot say whether one showed in the app's window at launch; a sheet already answered is not asked again")
    }

    /// A sheet has closed when nothing it brought is left, and not while any of it is — the app's own screen underneath does not count.
    ///
    /// Asked, as the runner asks, once the tapped control has gone.
    @Test
    func aSheetHasClosedWhenNothingItBroughtIsLeft() {
        let scope = SystemSheetScope(baseline: Self.onboarding())
        let sheetContinue = AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: 600, width: 362, height: 50), label: "Continue", identifier: "UIA.Health.Allow.Button")

        #expect(scope.hasClosed(sheetIn: Self.onboardingUnderSheet(), holding: sheetContinue, by: Self.onboarding(heading: "Welcome back")))
        #expect(!scope.hasClosed(sheetIn: Self.onboardingUnderSheet(), holding: sheetContinue, by: Self.onboardingUnderSheet(continueGone: true)))
    }

    /// A tapped control is looked for in the tree by what it is, never where its snapshot put it (SimWalk#47 review): the runner taps a coordinate and judges the control gone from a tree read, not from the element bound by index.
    ///
    /// The control is read 62 points off the tree's box, as a remote sheet's are, and is still held; with its label changed by the tap, or gone, it is not.
    @Test
    func aTappedControlIsHeldByWhatItIsNotWhereItsSnapshotPutIt() {
        let tapped = AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: 662, width: 362, height: 50), label: "Continue", identifier: "UIA.Health.Allow.Button")
        var relabelled = Self.onboardingUnderSheet()
        relabelled.children[0].children[1].children[0].children[0].children[0].label = "Continuing"

        #expect(SystemSheetScope.holds(tapped, in: Self.onboardingUnderSheet()))
        #expect(!SystemSheetScope.holds(tapped, in: relabelled))
        #expect(!SystemSheetScope.holds(tapped, in: Self.onboardingUnderSheet(continueGone: true)))
    }

    /// A sheet's tapped control is gone once its sheet has lost it, even where the app's own screen keeps an identical one (the #47 review): `stillHolds` answers false where `holds`, matching anywhere, still answers true — which would read the tap as never landed and keep the old baseline (SimWalk#39).
    @Test
    func aTappedSheetControlIsGoneWhileTheAppKeepsAnIdenticalOne() {
        let scope = SystemSheetScope(baseline: Self.onboarding())
        let tapped = AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: 600, width: 362, height: 50), label: "Continue")
        var underSheet = Self.onboarding()
        underSheet.children[0].children.append(AXNode(type: "Other", frame: Self.screen, children: [tapped]))
        let sheetGone = Self.onboarding()

        #expect(scope.stillHolds(tapped, in: underSheet))
        #expect(!scope.stillHolds(tapped, in: sheetGone))
        #expect(SystemSheetScope.holds(tapped, in: sheetGone))
    }

    /// The sheet is the new subtree that *lost* the control, not merely the last new subtree that happens to hold a match of it (SimWalk#42 item 1).
    ///
    /// A page appended after the sheet, holding an identical unidentified `Continue` that stays, must not be read as the sheet: the sheet's own `Continue` is gone, so the sheet has closed.
    @Test
    func theSubtreeThatLostTheControlIsTheSheetEvenWhenALaterSubtreeKeepsAMatch() {
        let scope = SystemSheetScope(baseline: Self.onboarding())
        let control = AXNode(type: "Button", frame: Self.continueFrame, label: "Continue")
        var before = Self.onboarding()
        before.children[0].children.append(AXNode(type: "Other", frame: Self.screen, identifier: "UIA.Health.AuthSheet", children: [control]))
        before.children[0].children.append(AXNode(type: "Other", frame: Self.screen, identifier: "health-setup", children: [control]))
        var after = Self.onboarding()
        after.children[0].children.append(AXNode(type: "Other", frame: Self.screen, identifier: "health-setup", children: [control]))

        #expect(scope.hasClosed(sheetIn: before, holding: control, by: after))
    }

    /// **Known limit** (SimWalk#42 item 2): a path is a chain of type and identifier, with no position among siblings.
    ///
    /// A page pushed where the sheet stood — both `Other` with no identifier, under the same parent — reads at the sheet's own path. The sheet's control is entirely gone, replaced by the app's own, yet `hasClosed` reads the sheet as still up.
    @Test
    func aPushedPageAtTheSheetsBarePathReadsAsTheSheetStillUp() {
        let scope = SystemSheetScope(baseline: Self.onboarding())
        let control = AXNode(type: "Button", frame: Self.continueFrame, label: "Continue", identifier: "UIA.Health.Allow.Button")
        var before = Self.onboarding()
        before.children[0].children.append(AXNode(type: "Other", frame: Self.screen, children: [control]))
        var after = Self.onboarding()
        after.children[0].children.append(AXNode(type: "Other", frame: Self.screen, children: [
            AXNode(type: "Button", frame: Self.continueFrame, label: "Allow"),
        ]))

        #expect(!scope.hasClosed(sheetIn: before, holding: control, by: after))
    }

    /// A live match the tree read holds none of is the snapshot's blindness, not an absent sheet (SimWalk#48): a remote sheet's content is in `app.snapshot()` only in the first session after its host process starts, so the refusal names the disagreement and the workaround — and only when the last poll that saw a match found the tree lacking it, since one poll's tree read a moment early is a race.
    @Test func aLiveMatchTheSnapshotDoesNotHoldIsNamedAsTheSnapshotsBlindness() {
        let scope = SystemSheetScope.admittingAll(of: Self.onboarding())
        let live = AXNode(type: "Cell", frame: AXNode.Frame(x: 22, y: 341, width: 358, height: 52), identifier: "UIA.Health.AuthSheet.AllCategoryButton")
        var holding = Self.onboarding()
        holding.children[0].children.append(live)
        var unseen = SystemSheetScope.PassedOver()
        unseen.poll([live], in: Self.onboarding())
        var raced = unseen
        raced.poll([live], in: holding)

        #expect(scope.refusal(for: "UIA.Health.AuthSheet.AllCategoryButton", passedOver: unseen, bootAge: nil) == "a 'UIA.Health.AuthSheet.AllCategoryButton' is on screen and reachable, and the app's snapshot does not hold it — most likely a remote sheet the snapshot cannot see (HealthKit's is hosted by com.apple.HealthPrivacyService); terminate the sheet's host process (xcrun simctl terminate <udid> <host bundle id>) or reboot, and walk again")
        #expect(!raced.unseenByTree)
        #expect(scope.refusal(for: "UIA.Health.AuthSheet.AllCategoryButton", passedOver: raced, bootAge: nil).hasPrefix("no enabled control"))
        #expect(scope.refusal(for: "Continue", passedOver: SystemSheetScope.PassedOver(), bootAge: nil) == scope.refusal(for: "Continue", passedOverAppOwn: false))
    }

    /// The app's own control of the same label, held and hittable beside a remote sheet's, does not hide the sheet's from the refusal (the 2026-09-23d review): the flag is set when any live match is missing from the tree, and a match is held only at its own box, so the remote `Allow` does not read as held because the app's identical `Allow` is.
    @Test func aRemoteMatchBesideTheAppsOwnIsStillNamedAsTheSnapshotsBlindness() {
        let appsAllow = AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: 700, width: 360, height: 50), label: "Allow", identifier: "allow")
        let sheetsAllow = AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: 500, width: 360, height: 50), label: "Allow", identifier: "allow")
        var tree = Self.onboarding()
        tree.children[0].children.append(appsAllow)
        var passedOver = SystemSheetScope.PassedOver()
        passedOver.poll([appsAllow, sheetsAllow], in: tree)
        var appsOnly = SystemSheetScope.PassedOver()
        appsOnly.poll([appsAllow], in: tree)

        #expect(passedOver.unseenByTree)
        #expect(passedOver.appOwn)
        #expect(!appsOnly.unseenByTree)
    }
}
