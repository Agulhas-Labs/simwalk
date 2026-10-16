//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// A `systemTap`'s baseline is the app's screen before the step that can raise its sheet, kept while that sheet is up and read again once it closes (SimWalk#39).
struct SystemSheetBaselineTests {
    private static let screen = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)
    private static let buttonFrame = AXNode.Frame(x: 20, y: 780, width: 362, height: 50)

    /// The app's home screen, a `Connect Health` button on it.
    private static let home = AXNode(type: "Application", frame: screen, label: "App", children: [
        AXNode(type: "Window", frame: screen, children: [
            AXNode(type: "Other", frame: screen, identifier: "home", children: [
                AXNode(type: "Button", frame: buttonFrame, label: "Connect Health"),
            ]),
        ]),
    ])

    /// The page `Connect Health` pushes on a device that has already answered: the app's own, with a list of its own and an identified `Continue`, and no sheet.
    private static let connectedPage = AXNode(type: "Application", frame: screen, label: "App", children: [
        AXNode(type: "Window", frame: screen, children: [
            AXNode(type: "Other", frame: screen, identifier: "health-connected", children: [
                AXNode(type: "Table", frame: screen, children: [AXNode(type: "Cell", frame: screen, label: "Steps")]),
                AXNode(type: "Button", frame: buttonFrame, label: "Continue", identifier: "connected.continue"),
            ]),
        ]),
    ])

    private static let pagesContinue = AXNode(type: "Button", frame: buttonFrame, label: "Continue", identifier: "connected.continue")

    /// `tree` with a sheet hosted in its window, holding `button`.
    private static func underSheet(_ tree: AXNode, holding button: AXNode, sheet: String = "UIA.Health.AuthSheet") -> AXNode {
        var tree = tree
        tree.children[0].children.append(AXNode(type: "Other", frame: screen, identifier: sheet, children: [button]))
        return tree
    }

    /// `tree` with the app's setup page pushed over its home: a navigation bar of its own, and a button of its own that became a spinner.
    private static func pushed(_ tree: AXNode) -> AXNode {
        var tree = tree
        tree.children[0].children.append(AXNode(type: "NavigationBar", frame: screen, identifier: "Health Setup"))
        tree.children[0].children[0].children.append(AXNode(type: "ActivityIndicator", frame: buttonFrame, label: "In progress"))
        return tree
    }

    /// `tree` with a page of the app's own pushed over its home, holding `control`.
    private static func withPage(_ tree: AXNode, holding control: AXNode) -> AXNode {
        var tree = tree
        tree.children[0].children.append(AXNode(type: "Other", frame: screen, identifier: "health-setup", children: [control]))
        return tree
    }

    /// `tree` with the app's own notifications primer over it, an `Allow` of its own.
    private static func underPrimer(_ tree: AXNode) -> AXNode {
        var tree = tree
        tree.children[0].children.append(AXNode(type: "Other", frame: screen, identifier: "notifications-primer", children: [
            AXNode(type: "Button", frame: buttonFrame, label: "Allow"),
        ]))
        return tree
    }

    /// Scenario A is the known limit (the #39 review's ruling): the baseline is read before the step, so a page that step pushed — the app's own `Continue`, on a device that has already answered — reads as new and is admitted.
    ///
    /// Pinned so the limit the README states is the one the code has.
    @Test
    func whatTheStepBeforeBroughtInReadsAsNew() throws {
        var baseline = SystemSheetBaseline()

        #expect(try baseline.scope(for: .tap(label: "Connect Health")) { Self.home } == nil)
        baseline.landed(.tap(label: "Connect Health"), sheetClosed: false)
        let scope = try #require(baseline.scope(for: .systemTap(label: "Continue")) { Self.connectedPage })

        #expect(scope.admits(Self.pagesContinue, in: Self.connectedPage))
    }

    /// A route that begins with a `systemTap` reads the launch's screen, and a sheet already up by then is in it: nothing of it is admitted, and the step says it is ambiguous.
    @Test
    func aSheetUpAtTheLaunchReadIsAmbiguous() throws {
        var baseline = SystemSheetBaseline(route: [.systemTap(label: "Allow")])
        let allow = AXNode(type: "Button", frame: Self.buttonFrame, label: "Allow", identifier: "UIA.Health.Allow.Button")
        let sheetUp = Self.underSheet(Self.home, holding: allow)

        let scope = try #require(baseline.scope(for: .systemTap(label: "Allow")) { sheetUp })

        #expect(!scope.admits(allow, in: sheetUp))
        #expect(scope.refusal(for: "Allow", passedOverAppOwn: true).contains("ambiguous"))
    }

    /// The ambiguous refusal of a launch read names the declaration that takes the sheet on the author's word; one read before a later step does not, since only a route's first step can make it (SimWalk#39 item 2).
    @Test
    func anAmbiguousLaunchReadNamesTheAtLaunchDeclaration() throws {
        let allow = AXNode(type: "Button", frame: Self.buttonFrame, label: "Allow", identifier: "UIA.Health.Allow.Button")
        let sheetUp = Self.underSheet(Self.home, holding: allow)
        let declaration = #"{"systemTap":{"label":"Allow","atLaunch":true}}"#
        var atLaunch = SystemSheetBaseline(route: [.systemTap(label: "Allow")])
        var afterTap = SystemSheetBaseline(route: [.tap(label: "Connect Health"), .systemTap(label: "Allow")])
        #expect(try afterTap.scope(for: .tap(label: "Connect Health")) { sheetUp } == nil)
        afterTap.landed(.tap(label: "Connect Health"), sheetClosed: false)

        let launchScope = try #require(atLaunch.scope(for: .systemTap(label: "Allow")) { sheetUp })
        let laterScope = try #require(afterTap.scope(for: .systemTap(label: "Allow")) { sheetUp })

        #expect(launchScope.refusal(for: "Allow", passedOverAppOwn: true).contains(declaration))
        #expect(laterScope.refusal(for: "Allow", passedOverAppOwn: true).contains("ambiguous"))
        #expect(!laterScope.refusal(for: "Allow", passedOverAppOwn: true).contains("atLaunch"))
    }

    /// A route whose first step is declared `atLaunch` takes the sheet's control from the launch's screen, sheet already up and all; the scope is kept while the sheet is up and read again once it closes (SimWalk#46).
    ///
    /// The closure here is passed as `sheetClosed: true` by hand: this pins the baseline's bookkeeping, not what the runner can produce, which for a sheet in the app's window never reads as closed under this scope.
    @Test
    func aSheetDeclaredAtLaunchIsAdmittedFromTheLaunchsScreen() throws {
        let allCategories = AXNode(type: "Button", frame: Self.buttonFrame, label: "Turn On All", identifier: "UIA.Health.AuthSheet.AllCategoryButton")
        let allow = AXNode(type: "Button", frame: Self.buttonFrame, label: "Allow", identifier: "UIA.Health.Allow.Button")
        let table = AXNode(type: "Table", frame: Self.screen, children: [allCategories])
        let launched = Self.underSheet(Self.home, holding: table)
        let allowPage = Self.underSheet(Self.home, holding: allow)
        let route: [Walkbook.RouteStep] = [
            .systemTap(label: "UIA.Health.AuthSheet.AllCategoryButton", atLaunch: true),
            .systemTap(label: "UIA.Health.Allow.Button"),
            .systemTap(label: "Allow"),
        ]
        var baseline = SystemSheetBaseline(route: route)

        let first = try #require(baseline.scope(for: route[0]) { launched })
        #expect(first.admits(allCategories, in: launched))
        #expect(first.scrollContainer(in: launched)?.node == table)
        baseline.landed(.systemTap(label: "UIA.Health.AuthSheet.AllCategoryButton", atLaunch: true, owner: .appWindow), sheetClosed: false)

        let second = try #require(baseline.scope(for: route[1]) { allowPage })
        #expect(second.admits(allow, in: allowPage))
        baseline.landed(.systemTap(label: "UIA.Health.Allow.Button", owner: .appWindow), sheetClosed: true)

        let primer = Self.underPrimer(Self.home)
        let third = try #require(baseline.scope(for: route[2]) { primer })
        #expect(!third.admits(AXNode(type: "Button", frame: Self.buttonFrame, label: "Allow"), in: primer))
    }

    /// The same launch without the declaration is #39 item 2's fail-safe, unchanged: the control was on the launch's screen, so it is not admitted and the step is named ambiguous.
    @Test
    func aSheetUpAtLaunchWithoutTheDeclarationIsStillRefused() throws {
        let allCategories = AXNode(type: "Button", frame: Self.buttonFrame, label: "Turn On All", identifier: "UIA.Health.AuthSheet.AllCategoryButton")
        let launched = Self.underSheet(Self.home, holding: AXNode(type: "Table", frame: Self.screen, children: [allCategories]))
        let step = Walkbook.RouteStep.systemTap(label: "UIA.Health.AuthSheet.AllCategoryButton")
        var baseline = SystemSheetBaseline(route: [step])

        let scope = try #require(baseline.scope(for: step) { launched })

        #expect(!scope.admits(allCategories, in: launched))
        #expect(scope.refusal(for: "UIA.Health.AuthSheet.AllCategoryButton", passedOverAppOwn: true).contains("ambiguous"))
    }

    /// The pattern that has to keep working: a sheet that arrives after the step that asked for it — the launch here — is admitted.
    @Test
    func aSheetThatArrivesAfterTheReadIsAdmitted() throws {
        var baseline = SystemSheetBaseline()
        let allow = AXNode(type: "Button", frame: Self.buttonFrame, label: "Continue", identifier: "UIA.Health.Allow.Button")

        let scope = try #require(baseline.scope(for: .systemTap(label: "UIA.Health.Allow.Button")) { Self.home })

        #expect(scope.admits(allow, in: Self.underSheet(Self.home, holding: allow)))
    }

    /// A sheet still up keeps the scope it was read for — its next page's control is still new — and nothing is read again.
    @Test
    func aSheetStillUpKeepsItsBaseline() throws {
        var baseline = SystemSheetBaseline()
        let turnOnAll = AXNode(type: "Button", frame: Self.buttonFrame, label: "Turn On All")
        let pastThirtyDays = AXNode(type: "Cell", frame: Self.buttonFrame, label: "Past 30 Days and Future Data")
        let firstPage = Self.underSheet(Self.home, holding: turnOnAll)
        let secondPage = Self.underSheet(Self.home, holding: pastThirtyDays)

        let first = try #require(baseline.scope(for: .systemTap(label: "Turn On All")) { Self.home })
        #expect(!first.hasClosed(sheetIn: firstPage, holding: turnOnAll, by: secondPage))
        baseline.landed(.systemTap(label: "Turn On All", owner: .appWindow), sheetClosed: false)
        let second = try #require(baseline.scope(for: .systemTap(label: "Past 30 Days and Future Data")) { secondPage })

        #expect(second.admits(pastThirtyDays, in: secondPage))
    }

    /// Scenario B: once the sheet has closed the app shows its own primer, and the next `systemTap 'Allow'` reads the screen again rather than taking the primer's `Allow` for SpringBoard's.
    @Test
    func aSheetThatClosedIsReadAgain() throws {
        var baseline = SystemSheetBaseline()
        let allow = AXNode(type: "Button", frame: Self.buttonFrame, label: "Allow", identifier: "UIA.Health.Allow.Button")
        let sheetUp = Self.underSheet(Self.home, holding: allow)
        let primer = Self.underPrimer(Self.home)

        let first = try #require(baseline.scope(for: .systemTap(label: "Allow")) { Self.home })
        let closed = first.hasClosed(sheetIn: sheetUp, holding: allow, by: primer)
        #expect(closed)
        baseline.landed(.systemTap(label: "Allow", owner: .appWindow), sheetClosed: closed)
        let second = try #require(baseline.scope(for: .systemTap(label: "Allow")) { primer })

        #expect(!second.admits(AXNode(type: "Button", frame: Self.buttonFrame, label: "Allow"), in: primer))
    }

    /// A `tap` whose only effect is to raise the sheet lands *on* the sheet — the change `tap` waits for is the sheet — so the baseline is the screen before that tap, and the sheet's `Allow`, there from the start and disabled, is the sheet's (the #39 review's finding 1).
    ///
    /// Replayed with the route known, as the runner makes it, so the read before the `tap` is pinned where a `systemTap` is still to come.
    @Test
    func aSheetTheStepBeforeRaisedIsAdmitted() throws {
        var baseline = SystemSheetBaseline(route: [.tap(label: "Connect Health"), .systemTap(label: "Allow")])
        let allow = AXNode(type: "Button", frame: Self.buttonFrame, label: "Allow", identifier: "UIA.Health.Allow.Button")
        let sheetUp = Self.underSheet(Self.home, holding: allow)
        var screen = Self.home

        #expect(try baseline.scope(for: .tap(label: "Connect Health")) { screen } == nil)
        screen = sheetUp
        baseline.landed(.tap(label: "Connect Health"), sheetClosed: false)
        let scope = try #require(baseline.scope(for: .systemTap(label: "Allow")) { screen })

        #expect(scope.admits(allow, in: sheetUp))
        #expect(!scope.refusal(for: "Allow", passedOverAppOwn: false).contains("ambiguous"))
    }

    /// A sheet over a page the step before pushed has closed once the sheet has gone, though the page stays (the final review's finding 1).
    ///
    /// `tap 'Connect Health'` pushes the app's setup page and that page raises HealthKit's sheet: the page is new against the baseline too, and stays once the sheet has gone. Only the sheet's own subtree decides, so the sheet reads as closed, the next `systemTap 'Allow'` reads the screen again, and the app's own primer is not admitted.
    @Test
    func aSheetOverAPageTheStepBeforePushedClosesWhileThePageStays() throws {
        let route: [Walkbook.RouteStep] = [.tap(label: "Connect Health"), .systemTap(label: "Allow"), .systemTap(label: "Allow")]
        var baseline = SystemSheetBaseline(route: route)
        let allow = AXNode(type: "Button", frame: Self.buttonFrame, label: "Allow", identifier: "UIA.Health.Allow.Button")
        let setupPage = Self.pushed(Self.home)
        let sheetUp = Self.underSheet(setupPage, holding: allow)
        let primer = Self.underPrimer(setupPage)

        #expect(try baseline.scope(for: route[0]) { Self.home } == nil)
        baseline.landed(route[0], sheetClosed: false)
        let first = try #require(baseline.scope(for: route[1]) { sheetUp })
        #expect(first.admits(allow, in: sheetUp))
        #expect(first.closing(sheetIn: sheetUp, holding: allow, by: setupPage, elapsed: 0, within: 2) == .closed)
        let closed = first.hasClosed(sheetIn: sheetUp, holding: allow, by: primer)
        #expect(closed)
        baseline.landed(.systemTap(label: "Allow", owner: .appWindow), sheetClosed: closed)
        let second = try #require(baseline.scope(for: route[2]) { primer })

        #expect(!second.admits(AXNode(type: "Button", frame: Self.buttonFrame, label: "Allow"), in: primer))
    }

    /// The sheet's second page under the same container, over a page the step before pushed, is the sheet still up: the page does not make it read as closed.
    @Test
    func aSheetsSecondPageOverAPushedPageIsStillUp() {
        let turnOnAll = AXNode(type: "Button", frame: Self.buttonFrame, label: "Turn On All")
        let setupPage = Self.pushed(Self.home)
        let firstPage = Self.underSheet(setupPage, holding: turnOnAll)
        let secondPage = Self.underSheet(setupPage, holding: AXNode(type: "Cell", frame: Self.buttonFrame, label: "Past 30 Days and Future Data"))
        let scope = SystemSheetScope(baseline: Self.home)

        #expect(scope.closing(sheetIn: firstPage, holding: turnOnAll, by: secondPage, elapsed: 2, within: 2) == .stillUp)
    }

    /// A page the step before pushed, holding a control just like the sheet's, does not keep the sheet up once the sheet's control has gone (the third review's finding 1).
    ///
    /// Both `Continue`s are unidentified, so both subtrees match by type, label and identifier, and the frame favours the page: the sheet's snapshot frame is 62 points off the live element's. The page's `Continue` is still there after the tap, so its page is not the sheet; the sheet reads as closed, and the app's primer after it is not admitted.
    @Test
    func aPagesControlLikeTheSheetsDoesNotKeepTheSheetUp() throws {
        let route: [Walkbook.RouteStep] = [.tap(label: "Connect Health"), .systemTap(label: "Continue"), .systemTap(label: "Allow")]
        var baseline = SystemSheetBaseline(route: route)
        let live = AXNode(type: "Button", frame: Self.buttonFrame, label: "Continue")
        let inSheet = AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: 718, width: 362, height: 50), label: "Continue")
        let setupPage = Self.withPage(Self.home, holding: live)
        let sheetUp = Self.underSheet(setupPage, holding: inSheet)
        let primer = Self.underPrimer(setupPage)

        #expect(try baseline.scope(for: route[0]) { Self.home } == nil)
        baseline.landed(route[0], sheetClosed: false)
        let first = try #require(baseline.scope(for: route[1]) { sheetUp })
        let closing = first.closing(sheetIn: sheetUp, holding: live, by: setupPage, elapsed: 0, within: 2)
        #expect(closing == .closed)
        baseline.landed(.systemTap(label: "Continue", owner: .appWindow), sheetClosed: closing == .closed)
        let second = try #require(baseline.scope(for: route[2]) { primer })

        #expect(!second.admits(AXNode(type: "Button", frame: Self.buttonFrame, label: "Allow"), in: primer))
    }

    /// Where more than one new subtree has lost a match, the frontmost is the sheet: a page behind it whose own `Continue` became a spinner does not keep the sheet up.
    @Test
    func theFrontmostSubtreeThatLostTheControlIsTheSheet() {
        let tapped = AXNode(type: "Button", frame: Self.buttonFrame, label: "Continue")
        let pageNowBusy = Self.withPage(Self.home, holding: AXNode(type: "ActivityIndicator", frame: Self.buttonFrame, label: "In progress"))
        let sheetUp = Self.underSheet(Self.withPage(Self.home, holding: tapped), holding: tapped)
        let scope = SystemSheetScope(baseline: Self.home)

        #expect(scope.hasClosed(sheetIn: sheetUp, holding: tapped, by: pageNowBusy))
    }

    /// Where no new subtree held the tapped control, the sheet reads as closed: the side that costs at most a false UNREACHABLE, not the one that keeps a baseline the app's primer could pass (the third review's finding 2).
    @Test
    func aControlNoNewSubtreeHeldReadsAsClosed() {
        let sheetUp = Self.underSheet(Self.home, holding: AXNode(type: "Button", frame: Self.buttonFrame, label: "Turn On All"))
        let scope = SystemSheetScope(baseline: Self.home)

        #expect(scope.hasClosed(sheetIn: sheetUp, holding: AXNode(type: "Button", frame: Self.buttonFrame, label: "Allow"), by: sheetUp))
    }

    /// A route with no `systemTap` never reads the screen for one.
    @Test
    func aRouteWithNoSystemTapReadsNothing() throws {
        let route: [Walkbook.RouteStep] = [.tab(label: "Home"), .tap(label: "Connect Health"), .back]
        var baseline = SystemSheetBaseline(route: route)
        var reads = 0

        for step in route {
            _ = try baseline.scope(for: step) {
                reads += 1
                return Self.home
            }
            baseline.landed(step, sheetClosed: false)
        }

        #expect(reads == 0)
    }

    /// Once the last `systemTap` has been asked for, the steps after it read nothing; before it, each does.
    @Test
    func stepsAfterTheLastSystemTapReadNothing() throws {
        let route: [Walkbook.RouteStep] = [.tap(label: "Connect Health"), .systemTap(label: "Allow"), .tab(label: "Home"), .back]
        var baseline = SystemSheetBaseline(route: route)
        var reads = 0

        for step in route {
            _ = try baseline.scope(for: step) {
                reads += 1
                return Self.home
            }
            baseline.landed(step, sheetClosed: false)
        }

        #expect(reads == 1)
    }

    /// **An index `steps` has no entry for falls back to the default quiet, rather than trapping** — a baseline made from a route alone (`init(route:)`) never fills `steps`, so `scope(forStep:from:)` still has to answer any index the runner asks it for (SimWalk#56).
    @Test
    func anIndexWithNoStepFallsBackToTheDefaultQuiet() throws {
        let route: [Walkbook.RouteStep] = [.tap(label: "Connect Health"), .systemTap(label: "Allow")]
        var baseline = SystemSheetBaseline(route: route)
        let screen = ScriptedScreen([Self.home])

        let read = try baseline.scope(forStep: 0, from: screen)

        #expect(read == nil)
        #expect(screen.reads == 1)
    }

    /// A sheet whose control has gone but whose container is still animating out is read again, not answered as still up — so the baseline is dropped once it has closed, and the app's primer behind it is not admitted (the #39 review's finding 3).
    @Test
    func aSheetStillAnimatingOutIsReadAgain() {
        let allow = AXNode(type: "Button", frame: Self.buttonFrame, label: "Allow", identifier: "UIA.Health.Allow.Button")
        let sheetUp = Self.underSheet(Self.home, holding: allow)
        let animatingOut = Self.underSheet(Self.home, holding: AXNode(type: "Other", frame: Self.buttonFrame))
        let scope = SystemSheetScope(baseline: Self.home)

        #expect(scope.closing(sheetIn: sheetUp, holding: allow, by: animatingOut, elapsed: 0, within: 2) == .readAgain)
        #expect(scope.closing(sheetIn: sheetUp, holding: allow, by: animatingOut, elapsed: 1.9, within: 2) == .readAgain)
        #expect(scope.closing(sheetIn: sheetUp, holding: allow, by: Self.underPrimer(Self.home), elapsed: 2.1, within: 2) == .closed)
        #expect(scope.closing(sheetIn: sheetUp, holding: allow, by: animatingOut, elapsed: 2, within: 2) == .stillUp)
    }

    /// Scenario B with the primer late: the sheet has gone, and the app puts up a page with an identified `Allow` of its own a few reads later.
    ///
    /// The first read after the close waits for the screen to settle, so the page is in the baseline and the next `systemTap 'Allow'` does not take it (SimWalk#39 item 1).
    @Test
    func aPageTheAppPutsUpAMomentAfterTheSheetClosedIsNotAdmitted() throws {
        let route: [Walkbook.RouteStep] = [.systemTap(label: "Allow"), .systemTap(label: "Allow")]
        var baseline = SystemSheetBaseline(route: route)
        let appsAllow = AXNode(type: "Button", frame: Self.buttonFrame, label: "Allow", identifier: "notifications.allow")
        let primerPage = Self.withPage(Self.home, holding: appsAllow)
        let lateScreen = ScriptedScreen([Self.home, Self.home, primerPage])
        _ = try baseline.scope(for: route[0], from: ScriptedScreen([Self.home]), quiet: 0.5)
        baseline.landed(.systemTap(label: "Allow", owner: .appWindow), sheetClosed: true)

        let read = try baseline.scope(for: route[1], from: lateScreen, quiet: 0.5)
        let second = try #require(read)

        #expect(!second.admits(appsAllow, in: primerPage))
    }

    /// **A walkbook screen's baseline waits under the quiet period of the screen its step is taken on** (SimWalk#55).
    ///
    /// The screen `[systemTap 'Allow']` leads to states `settle: 2000`, and its app's primer arrives a second after the sheet closed. Under the walk's own half second the read would be taken before it, and the primer's `Allow` admitted as the sheet's.
    @Test
    func aStepsBaselineWaitsUnderTheQuietPeriodOfTheScreenItIsTakenOn() throws {
        let sheet = Walkbook.Screen(id: "sheet", route: [.systemTap(label: "Allow")], states: [Walkbook.CaptureState(theme: .light)], settle: 2000)
        let primer = Walkbook.Screen(id: "primer", route: [.systemTap(label: "Allow"), .systemTap(label: "Allow")], states: [Walkbook.CaptureState(theme: .light)])
        let book = Walkbook(name: "walk", appBundleID: "com.example", screens: [sheet, primer])
        var baseline = SystemSheetBaseline(screen: primer, of: book, defaultQuiet: 0.5)
        let appsAllow = AXNode(type: "Button", frame: Self.buttonFrame, label: "Allow", identifier: "notifications.allow")
        let primerPage = Self.withPage(Self.home, holding: appsAllow)
        let lateScreen = ScriptedScreen(Array(repeating: Self.home, count: 5) + [primerPage])
        _ = try baseline.scope(forStep: 0, from: ScriptedScreen([Self.home]))
        baseline.landed(.systemTap(label: "Allow", owner: .appWindow), sheetClosed: true)

        let read = try baseline.scope(forStep: 1, from: lateScreen)
        let second = try #require(read)

        #expect(!second.admits(appsAllow, in: primerPage))
    }

    /// A read with no sheet closed before it is one read, not a watch: a sheet the step raises has to arrive after it to be new (SimWalk#39 item 1).
    @Test
    func aReadWithNoSheetClosedBeforeItIsASingleRead() throws {
        let route: [Walkbook.RouteStep] = [.tap(label: "Connect Health"), .systemTap(label: "Allow")]
        var baseline = SystemSheetBaseline(route: route)
        let allow = AXNode(type: "Button", frame: Self.buttonFrame, label: "Allow", identifier: "UIA.Health.Allow.Button")
        let sheetUp = Self.underSheet(Self.home, holding: allow)
        let screen = ScriptedScreen([Self.home, sheetUp])
        #expect(try baseline.scope(for: route[0], from: screen, quiet: 0.5) == nil)
        baseline.landed(route[0], sheetClosed: false)

        let read = try baseline.scope(for: route[1], from: screen, quiet: 0.5)
        let scope = try #require(read)

        #expect(screen.reads == 1)
        #expect(scope.admits(allow, in: sheetUp))
    }

    /// The declaration the ambiguous refusal names is valid JSON whatever the label holds (the 2026-09-23d review): a quote or backslash in it is escaped, so the line pastes in as written.
    @Test func theNamedDeclarationEscapesTheLabel() throws {
        let label = #"Don't "Allow" \ now"#
        let allow = AXNode(type: "Button", frame: Self.buttonFrame, label: label, identifier: nil)
        var atLaunch = SystemSheetBaseline(route: [.systemTap(label: label)])
        let scope = try #require(atLaunch.scope(for: .systemTap(label: label)) { Self.underSheet(Self.home, holding: allow) })

        #expect(scope.refusal(for: label, passedOverAppOwn: true).contains(#"{"systemTap":{"label":"Don't \"Allow\" \\ now","atLaunch":true}}"#))
    }
}

private extension SystemSheetBaselineTests {
    /// The app's screen replayed read by read — each read the next tree, the last one held — on a clock only the pauses advance.
    final class ScriptedScreen: TreeSource {
        private let trees: [AXNode]
        private var clock: TimeInterval = 0
        private(set) var reads = 0

        init(_ trees: [AXNode]) {
            self.trees = trees
        }

        func appTree() throws -> AXNode {
            reads += 1
            return trees[min(reads, trees.count) - 1]
        }

        func elapsed() -> TimeInterval {
            clock
        }

        func pause(_ interval: TimeInterval) {
            clock += interval
        }
    }

    /// A screen that reads `tree` every time.
    struct ReadEachTime: TreeSource {
        let tree: () -> AXNode

        func appTree() throws -> AXNode {
            tree()
        }

        func elapsed() -> TimeInterval {
            0
        }

        func pause(_: TimeInterval) {}
    }
}

private extension SystemSheetBaseline {
    /// `scope(for:from:quiet:)` against a screen that reads `tree` every time, as the tests before SimWalk#39's settled read were written.
    mutating func scope(for step: Walkbook.RouteStep, reading tree: @escaping () -> AXNode) throws -> SystemSheetScope? {
        try scope(for: step, from: SystemSheetBaselineTests.ReadEachTime(tree: tree), quiet: SettleWindow.interval)
    }
}
