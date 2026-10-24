//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// `discover` drafts a walkbook by tapping only what navigates, so these hold it to what it sends as much as to what it writes.
struct DiscoverCrawlTests {
    @Test
    func onlyTabsDisclosureRowsAndTheBackButtonAreEverSent() throws {
        let app = Self.settingsLike()

        _ = try Self.crawl(app)

        let rows: Set = ["General", "Privacy", "About", "Storage"]
        #expect(!app.sent.isEmpty)
        for step in app.sent {
            switch step {
            case let .tab(label):
                #expect(["Settings", "Profile"].contains(label))
            case let .tap(label), let .scrollTo(label):
                #expect(rows.contains(label))
            case .back:
                break
            default:
                Issue.record("sent \(step)")
            }
        }
        #expect(app.sent.contains(.back))
    }

    /// A destructive button looks like any other button, so no button that is not a disclosure row is ever tapped.
    @Test
    func aDestructiveButtonAPlainButtonASwitchAndATextFieldAreNeverSentAndAreListedWithTheirReasons() throws {
        let app = Self.settingsLike()

        let result = try Self.crawl(app)

        #expect(!app.tapped.contains("Erase All Content"))
        #expect(!app.tapped.contains("Share"))
        #expect(!app.tapped.contains("Airplane Mode"))
        #expect(!app.tapped.contains("Name"))
        let reasons = Dictionary(result.skipped.map { ($0.name, $0.reason) }) { first, _ in first }
        #expect(reasons["Erase All Content"] == .notNavigation)
        #expect(reasons["Share"] == .notNavigation)
        #expect(reasons["Airplane Mode"] == .isSwitch)
        #expect(reasons["Name"] == .textField)
        #expect(result.lines().contains("  Button 'Erase All Content': not a navigation affordance"))
    }

    @Test
    func aSystemAlertOverThePushedScreenEndsItsBranchAndIsReported() throws {
        let app = FakeDiscoveryApp(launch: "root", screens: [
            "root": FakeDiscoveryApp.Screen(title: "Root", rows: ["Notifications", "About"], taps: ["Notifications": "prompt", "About": "about"]),
            "prompt": FakeDiscoveryApp.Screen(title: "Alerts", back: true, rows: ["Sounds"], systemAlert: ["Don't Allow", "Allow"], taps: ["Sounds": "sounds"]),
            "sounds": FakeDiscoveryApp.Screen(title: "Sounds", back: true, texts: ["Tone"]),
            "about": FakeDiscoveryApp.Screen(title: "About", back: true, texts: ["Version"]),
        ])

        let result = try Self.crawl(app)

        #expect(!app.tapped.contains("Allow"))
        #expect(!app.tapped.contains("Don't Allow"))
        #expect(!app.tapped.contains("Sounds"))
        #expect(result.walkbook.screens.map(\.id) == ["root", "about"])
        #expect(result.skipped.contains { $0.name == "Notifications" && $0.reason == .alertEndsBranch })
        #expect(result.skipped.filter { $0.reason == .alertButton }.map(\.name) == ["Don't Allow", "Allow"])
        #expect(app.relaunches == 1)
    }

    @Test
    func anAlertEndsItsBranchAndIsReported() throws {
        let app = FakeDiscoveryApp(launch: "root", screens: [
            "root": FakeDiscoveryApp.Screen(title: "Root", rows: ["Reset", "About"], taps: ["Reset": "confirm", "About": "about"]),
            "confirm": FakeDiscoveryApp.Screen(title: "Root", rows: ["Reset", "About"], alert: ["Cancel", "Erase"]),
            "about": FakeDiscoveryApp.Screen(title: "About", back: true, texts: ["Version"]),
        ])

        let result = try Self.crawl(app)

        #expect(!app.tapped.contains("Erase"))
        #expect(!app.tapped.contains("Cancel"))
        #expect(result.walkbook.screens.map(\.id) == ["root", "about"])
        #expect(result.skipped.contains { $0.name == "Reset" && $0.reason == .alertEndsBranch })
        #expect(result.skipped.filter { $0.reason == .alertButton }.map(\.name) == ["Cancel", "Erase"])
        #expect(app.relaunches == 1)
    }

    /// A pushed screen with no back button — a full-screen presentation — is left by relaunching and replaying the route to its parent, never by a `back` it would answer with nothing, or with whatever its first bar button is.
    @Test
    func aScreenWithNoBackButtonIsReturnedFromByRelaunchAndReplay() throws {
        let app = FakeDiscoveryApp(launch: "home", tabs: ["Home": "home"], screens: [
            "home": FakeDiscoveryApp.Screen(title: "Home", rows: ["Player", "Library"], tabs: ["Home"], taps: ["Player": "player", "Library": "library"]),
            "player": FakeDiscoveryApp.Screen(identifier: "player", texts: ["Now playing"]),
            "library": FakeDiscoveryApp.Screen(title: "Library", back: true, texts: ["Albums"], tabs: ["Home"]),
        ])

        let result = try Self.crawl(app)

        #expect(app.relaunches == 1)
        #expect(app.sent == [.tab(label: "Home"), .tap(label: "Player"), .tab(label: "Home"), .tap(label: "Library"), .back])
        #expect(result.walkbook.screens.map(\.route) == [
            [.tab(label: "Home")],
            [.tab(label: "Home"), .tap(label: "Player")],
            [.tab(label: "Home"), .tap(label: "Library")],
        ])
    }

    @Test
    func twoScreensOfOneFormWithDifferentValuesAreDraftedOnce() throws {
        let app = FakeDiscoveryApp(launch: "list", screens: [
            "list": FakeDiscoveryApp.Screen(title: "Passages", rows: ["Passage 1", "Passage 2"], taps: ["Passage 1": "one", "Passage 2": "two"]),
            "one": FakeDiscoveryApp.Screen(title: "Passage 1", identifier: "passage-detail", back: true, texts: ["8.2 nm", "09:10"]),
            "two": FakeDiscoveryApp.Screen(title: "Passage 2", identifier: "passage-detail", back: true, texts: ["7.9 nm", "10:05"]),
        ])

        let result = try Self.crawl(app)

        #expect(result.walkbook.screens.map(\.id) == ["root", "passage-1"])
        #expect(result.walkbook.screens.last?.expect == "passage-detail")
        #expect(result.duplicates == [DiscoverResult.Duplicate(route: [.scrollTo(label: "Passage 1"), .tap(label: "Passage 2")], screenID: "passage-1")])
        #expect(app.tapped == ["Passage 1", "Passage 2"])
    }

    @Test
    func theDepthBoundIsReportedWithTheAffordancesLeftUnvisited() throws {
        let app = Self.settingsLike()

        let result = try Self.crawl(app, depth: 0)

        #expect(app.tapped.isEmpty)
        #expect(result.unvisited(.beyondDepth) == 4)
        #expect(result.lines().first == "depth 0 reached: 4 affordances not visited")
    }

    @Test
    func theMaxScreensBoundIsReportedWithTheAffordancesLeftUnvisited() throws {
        let app = Self.settingsLike()

        let result = try Self.crawl(app, maxScreens: 2)

        #expect(result.walkbook.screens.count == 2)
        #expect(result.unvisited(.beyondMaxScreens) == 4)
        #expect(result.lines().first == "max screens 2 reached: 4 affordances not visited")
    }

    /// A `tap(label:)` route names a control by its label, so a row whose label another control on the screen also answers to could not be named by one.
    @Test
    func aRowWhoseLabelAnotherControlSharesIsSkippedAndNeverTapped() throws {
        let app = FakeDiscoveryApp(launch: "root", screens: [
            "root": FakeDiscoveryApp.Screen(title: "Root", rows: ["Notes", "Notes", "Mail"], taps: ["Notes": "notes", "Mail": "mail"]),
            "notes": FakeDiscoveryApp.Screen(title: "Notes", back: true),
            "mail": FakeDiscoveryApp.Screen(title: "Mail", back: true),
        ])

        let result = try Self.crawl(app)

        #expect(app.tapped == ["Mail"])
        #expect(result.skipped.filter { $0.reason == .labelNotUnique }.map(\.name) == ["Notes", "Notes"])
    }

    @Test
    func aRowBelowTheVisibleFrameIsScrolledToBeforeItIsTapped() throws {
        let rows = (1 ... 16).map { "Row \(Character(UnicodeScalar(64 + $0) ?? "A"))" }
        let app = FakeDiscoveryApp(launch: "home", tabs: ["Home": "home"], screens: [
            "home": FakeDiscoveryApp.Screen(title: "Home", rows: rows, tabs: ["Home"], taps: ["Row P": "detail"]),
            "detail": FakeDiscoveryApp.Screen(title: "Detail", back: true, tabs: ["Home"]),
        ])

        let result = try Self.crawl(app, maxScreens: 25)

        #expect(result.walkbook.screens.first { $0.id == "row-p" }?.route == [.tab(label: "Home"), .scrollTo(label: "Row P"), .tap(label: "Row P")])
    }

    /// A runner that cannot drag the list leaves the screen listed with why, and the verdict qualified, while a list that ends on screen says nothing.
    @Test
    func aListTheRunnerCannotScrollIsListedWithWhy() throws {
        let rows = (1 ... 20).map { "Item \(Character(UnicodeScalar(64 + $0) ?? "A"))" }
        let app = FakeDiscoveryApp(launch: "home", tabs: ["Home": "home", "Short": "short"], screens: [
            "home": FakeDiscoveryApp.Screen(title: "Home", rows: rows, tabs: ["Home", "Short"], table: true),
            "short": FakeDiscoveryApp.Screen(title: "Short", rows: ["Only"], tabs: ["Home", "Short"], table: true),
        ], scrollFails: ["home"])

        let result = try Self.crawl(app)

        #expect(app.relaunches == 0)
        #expect(result.belowTheFold == [DiscoverResult.OpenList(screenID: "home", why: "the runner could not scroll it")])
        #expect(result.lines().contains("home: the list may continue below the rows read; rows there were not read (the runner could not scroll it)"))
        let verdict = result.answer(header: "discover", output: "draft.json").verdict
        #expect(verdict.isQualified)
        #expect(verdict.line.contains("1 screen's list may continue below the fold, not read"))
    }

    /// The fixture's Hub: a lazy list of filler with its disclosure row far below the fold, which only dragging the list loads.
    @Test
    func aLazyListsRowBelowTheFoldIsDraftedWithScrollToThenTap() throws {
        let app = Self.lazyApp(rows: Self.filler(20) + ["Open form"], taps: ["Open form": "form"])

        let result = try Self.crawl(app)

        #expect(result.walkbook.screens.first { $0.id == "open-form" }?.route == [.tab(label: "Hub"), .scrollTo(label: "Open form"), .tap(label: "Open form")])
        #expect(result.belowTheFold.isEmpty)
        #expect(app.scrolls.contains(.down))
    }

    /// A screen identifier carried by a row of the list scrolls away with it, and says nothing about the screen.
    @Test
    func aScreenIdentifiedByARowInsideTheListIsPagedToItsEnd() throws {
        let rows = Self.filler(20) + ["Open form"]
        let hub = FakeDiscoveryApp.Screen(title: "Hub", rows: rows, tabs: ["Hub"], table: true, taps: ["Open form": "form"], plain: Set(Self.filler(20)), lazy: true, firstRowIdentifier: "hub-footer")
        let app = FakeDiscoveryApp(launch: "hub", tabs: ["Hub": "hub"], screens: ["hub": hub, "form": FakeDiscoveryApp.Screen(title: "form", back: true, tabs: ["Hub"])])

        let result = try Self.crawl(app)

        #expect(ScreenIdentifierRule.screenIdentifier(of: hub.tree) == "hub-footer")
        #expect(result.walkbook.screens.first { $0.id == "open-form" }?.route == [.tab(label: "Hub"), .scrollTo(label: "Open form"), .tap(label: "Open form")])
        #expect(result.belowTheFold.isEmpty)
    }

    /// An identifier outside the list that differs after a drag is another screen: the list is left open, with why.
    @Test
    func aScreenWhoseIdentifierOutsideTheListChangesWhileScrollingIsListedWithWhy() throws {
        let hub = FakeDiscoveryApp.Screen(title: "Hub", rows: Self.filler(20), tabs: ["Hub"], table: true, plain: Set(Self.filler(20)), lazy: true, outsideIdentifiers: (resting: "hub", scrolled: "elsewhere"))
        let app = FakeDiscoveryApp(launch: "hub", tabs: ["Hub": "hub"], screens: ["hub": hub])

        let result = try Self.crawl(app)

        #expect(result.belowTheFold == [DiscoverResult.OpenList(screenID: "hub", why: "the screen changed while scrolling")])
    }

    /// The container's own identifier usually names the screen: a drag that lands on a screen whose list has the same type and frame but another identifier is not the same screen.
    @Test
    func aScreenWhoseListContainerIdentifierChangesWhileScrollingIsListedWithWhy() throws {
        let hub = FakeDiscoveryApp.Screen(title: "Hub", identifier: "hub", rows: Self.filler(20), tabs: ["Hub"], table: true, plain: Set(Self.filler(20)), lazy: true, scrolledIdentifier: "detail")
        let app = FakeDiscoveryApp(launch: "hub", tabs: ["Hub": "hub"], screens: ["hub": hub])

        let result = try Self.crawl(app)

        #expect(result.belowTheFold == [DiscoverResult.OpenList(screenID: "hub", why: "the screen changed while scrolling")])
    }

    /// The first page's rows are tapped as on-screen rows, so the list must be back where it started: the tap on the first row finds it only at the top.
    @Test
    func theListIsDraggedBackBeforeItsFirstRowsAreTapped() throws {
        let app = Self.lazyApp(rows: ["First"] + Self.filler(20) + ["Last"], taps: ["First": "first-screen", "Last": "last-screen"])

        let result = try Self.crawl(app)

        #expect(app.scrolls == [.down, .down, .up, .up])
        #expect(app.hits == ["First", "Last"])
        #expect(result.walkbook.screens.map(\.id) == ["hub", "first", "last"])
        #expect(result.walkbook.screens.last?.route == [.tab(label: "Hub"), .scrollTo(label: "Last"), .tap(label: "Last")])
        #expect(result.belowTheFold.isEmpty)
    }

    /// A list left scrolled passes the form check when its rows share one text shape, so a list the runner dragged down but could not drag back up is relaunched, not trusted.
    @Test
    func aListTheRunnerCouldNotDragBackUpIsRelaunchedBeforeItsFirstRowIsTapped() throws {
        let app = Self.lazyApp(rows: ["Filler 0"] + Self.filler(24), taps: ["Filler 0": "first-screen"], upFails: ["hub"])

        let result = try Self.crawl(app)

        #expect(app.relaunches >= 1)
        #expect(app.hits.contains("Filler 0"))
        #expect(result.walkbook.screens.map(\.id).contains("filler-0"))
        #expect(result.belowTheFold.isEmpty)
    }

    /// A drag that moved nothing while the last row grew is not a page to join, and is not the end of the list either (SimWalk#208).
    @Test
    func aListThatChangesInPlaceOnADragIsListedWithWhy() throws {
        let app = Self.changingApp(drags: 1)

        let result = try Self.crawl(app)

        #expect(result.belowTheFold == [DiscoverResult.OpenList(screenID: "hub", why: "the list changed without scrolling")])
        #expect(app.relaunches == 0)
    }

    /// A drag up after which the list stayed put moved nothing, though the list changed: the drags up end there, with no relaunch.
    ///
    /// The fake has more drags than the crawl makes, so without that rule the drags up run out and the crawl relaunches.
    @Test
    func aDragUpThatLeavesTheListStayedPutWhileItChangesEndsTheDragsUpWithoutARelaunch() throws {
        let app = Self.changingApp(drags: 5)

        let result = try Self.crawl(app)

        #expect(app.scrolls == [.down, .up])
        #expect(app.relaunches == 0)
        #expect(result.belowTheFold == [DiscoverResult.OpenList(screenID: "hub", why: "the list changed without scrolling")])
    }

    /// A pinned header is the only anchor over rows that share one label, so rows dropping away under it leave every anchor in place: the list has not stayed put, and the drags up go on until they run out (SimWalk#208).
    @Test
    func aListWhoseOnlyAnchorIsAPinnedHeaderIsNotTakenAsAtItsTopWhileItsRowsDropAway() throws {
        func hub(photos: Int) -> FakeDiscoveryApp.Screen {
            let rows = ["Today"] + Array(repeating: "Photo", count: photos)
            return FakeDiscoveryApp.Screen(title: "Hub", rows: rows, tabs: ["Hub"], table: true, plain: Set(rows))
        }
        let app = FakeDiscoveryApp(launch: "hub", tabs: ["Hub": "hub"], screens: ["hub": hub(photos: 25)], changesOnDrag: ["hub": (1 ... 5).map { hub(photos: 25 - $0) }])

        _ = try Self.crawl(app)

        #expect(app.scrolls == [.down, .up, .up, .up])
    }

    /// The same pinned header over rows that keep their count but sit lower after each drag: the header stays and the rows moved, so the list has not stayed put (SimWalk#210).
    @Test
    func aListWhoseRowsMoveUnderAPinnedHeaderAtTheSameCountIsNotTakenAsAtItsTop() throws {
        func hub(gap: Double) -> FakeDiscoveryApp.Screen {
            let rows = ["Today"] + Array(repeating: "Photo", count: 25)
            return FakeDiscoveryApp.Screen(title: "Hub", rows: rows, tabs: ["Hub"], table: true, plain: Set(rows), gapAfterFirstRow: gap)
        }
        let app = FakeDiscoveryApp(launch: "hub", tabs: ["Hub": "hub"], screens: ["hub": hub(gap: 0)], changesOnDrag: ["hub": (1 ... 5).map { hub(gap: Double($0) * 10) }])

        _ = try Self.crawl(app)

        #expect(app.scrolls == [.down, .up, .up, .up])
    }

    /// A screen of 20 plain rows (not lazy, so a drag scrolls nothing) whose next `drags` drags each make the last row taller.
    static func changingApp(drags: Int) -> FakeDiscoveryApp {
        let rows = Self.filler(20)
        func hub(_ growth: Double) -> FakeDiscoveryApp.Screen {
            FakeDiscoveryApp.Screen(title: "Hub", rows: rows, tabs: ["Hub"], table: true, plain: Set(rows), lastRowGrowth: growth)
        }
        return FakeDiscoveryApp(launch: "hub", tabs: ["Hub": "hub"], screens: ["hub": hub(0)], changesOnDrag: ["hub": (1 ... drags).map { hub(Double($0) * 10) }])
    }

    @Test
    func aListPastThePageLimitIsListedWithWhy() throws {
        let rows = ["First"] + Self.filler(30) + ["Mid"] + Self.filler(100, prefix: "Far") + ["Last"]
        let app = Self.lazyApp(rows: rows, taps: ["First": "first-screen", "Mid": "mid-screen", "Last": "last-screen"])

        let result = try Self.crawl(app)

        #expect(result.belowTheFold == [DiscoverResult.OpenList(screenID: "hub", why: "stopped after 10 pages")])
        #expect(result.lines().contains("hub: the list may continue below the rows read; rows there were not read (stopped after 10 pages)"))
        #expect(result.answer(header: "discover", output: "draft.json").verdict.isQualified)
        #expect(app.scrolls.count { $0 == .down } == DiscoverCrawl.pageLimit - 1)
        #expect(app.hits == ["First", "Mid"])
    }

    /// `scrollTo` stops at whichever of two rows it meets first, so a label read at two places in the list names neither.
    @Test
    func aLabelReadAtTwoPlacesInTheListIsSkippedAndNeverTapped() throws {
        let app = Self.lazyApp(rows: ["Twice"] + Self.filler(20) + ["Twice"], taps: ["Twice": "twice-screen"])

        let result = try Self.crawl(app)
        let skips = result.skipped.filter { $0.reason == .labelNotUnique }

        #expect(skips.map(\.name) == ["Twice", "Twice"])
        #expect(skips[0].frame.y < skips[1].frame.y)
        #expect(app.hits.isEmpty)
        #expect(result.walkbook.screens.map(\.id) == ["hub"])
    }

    @Test
    func aScreenAtTheDepthBoundIsNotScrolledAndSaysWhy() throws {
        let app = Self.lazyApp(rows: Self.filler(20) + ["Open form"], taps: ["Open form": "form"])

        let result = try Self.crawl(app, depth: 0)

        #expect(app.scrolls.isEmpty)
        #expect(result.belowTheFold == [DiscoverResult.OpenList(screenID: "hub", why: "not scrolled: beyond depth")])
        #expect(result.lines().contains("hub: the list may continue below the rows read; rows there were not read (not scrolled: beyond depth)"))
    }

    /// A list's backgrounds reach the bottom whatever it holds — the fixture's two-row danger zone, frames as captured — so its rows are its cells: a short list says nothing, and the same list with a cell at the tab bar may continue.
    @Test
    func aShortListWhoseBackgroundsReachTheBottomIsNotReportedAsMayContinue() {
        func frame(_ y: Double, _ height: Double) -> AXNode.Frame {
            AXNode.Frame(x: 0, y: y, width: 420, height: height)
        }
        func screen(_ cells: [AXNode]) -> AXNode {
            let backgrounds = [AXNode(type: "Other", frame: frame(-1650, 3772)), AXNode(type: "Other", frame: frame(0, 912))]
            let list = AXNode(type: "CollectionView", frame: frame(0, 912), children: backgrounds + cells)
            return AXNode(type: "Application", frame: frame(0, 912), children: [list, AXNode(type: "TabBar", frame: frame(829, 83))])
        }
        let short = [AXNode(type: "Cell", frame: frame(174, 52)), AXNode(type: "Cell", frame: frame(226, 52))]

        #expect(!DiscoverClassifier.listMayContinue(screen(short)))
        #expect(DiscoverClassifier.listMayContinue(screen(short + [AXNode(type: "Cell", frame: frame(790, 52))])))
    }

    /// A scroll view has no cells, and its backgrounds are framed exactly as it is — the fixture's one-page and four-page scroll views, frames as captured — so its content, not its backgrounds, says whether it runs on.
    @Test
    func aScrollViewsBackgroundsAreNotItsContent() {
        func frame(_ y: Double, _ height: Double) -> AXNode.Frame {
            AXNode.Frame(x: 0, y: y, width: 420, height: height)
        }
        func screen(content: AXNode.Frame) -> AXNode {
            let children = [AXNode(type: "Other", frame: frame(0, 912)), AXNode(type: "Other", frame: frame(0, 912)), AXNode(type: "Other", frame: content)]
            let scroll = AXNode(type: "ScrollView", frame: frame(0, 912), children: children)
            return AXNode(type: "Application", frame: frame(0, 912), children: [scroll, AXNode(type: "TabBar", frame: frame(829, 83))])
        }

        #expect(!DiscoverClassifier.listMayContinue(screen(content: frame(174, 89))))
        #expect(DiscoverClassifier.listMayContinue(screen(content: frame(174, 2011))))
    }

    /// A cell and the button inside it carrying its label are one target to the runner's lookup, so the one that is not the row is not listed as a control left alone.
    @Test
    func aButtonInsideARowWithTheRowsLabelIsNotListedAsSkipped() {
        let glyph = AXNode(type: "Image", frame: AXNode.Frame(x: 378, y: 215, width: 8, height: 14))
        let inner = AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 204, width: 340, height: 36), label: "Sleep, 7h 12m")
        let row = AXNode(type: "Cell", frame: AXNode.Frame(x: 0, y: 200, width: 402, height: 44), label: "Sleep, 7h 12m", children: [inner, glyph])
        let share = AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 260, width: 370, height: 44), label: "Share")
        let tree = AXNode(type: "Application", frame: FakeDiscoveryApp.bounds, label: "Fake", children: [
            AXNode(type: "Window", frame: FakeDiscoveryApp.bounds, children: [
                AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 116, width: 402, height: 200), children: [row, share]),
            ]),
        ])

        let read = DiscoverClassifier.read(tree, screenID: "root")

        #expect(read.rows.map(\.label) == ["Sleep"])
        #expect(read.skipped.map(\.name) == ["Share"])
    }

    /// A relaunch can start the app in another state, where a replayed `tap 'Account'` would reach `Account, delete` by its leading component: the replay checks the screen is the one the row was tapped on before tapping, and stops the branch when it is not.
    @Test
    func aReplayAfterRelaunchNeverTapsAControlTheCrawlDidNotRecord() throws {
        let app = FakeDiscoveryApp(
            launch: "home",
            tabs: ["Home": "home"],
            screens: [
                "home": FakeDiscoveryApp.Screen(title: "Home", rows: ["Account"], tabs: ["Home"], taps: ["Account": "account"]),
                "account": FakeDiscoveryApp.Screen(title: "Account", back: true, rows: ["Profile", "Devices"], tabs: ["Home"], taps: ["Profile": "profile", "Devices": "devices"]),
                "profile": FakeDiscoveryApp.Screen(identifier: "profile", texts: ["Your profile"]),
                "devices": FakeDiscoveryApp.Screen(title: "Devices", back: true, tabs: ["Home"]),
            ],
            afterRelaunch: [
                "home": FakeDiscoveryApp.Screen(title: "Home", controls: [(type: "Button", label: "Account, delete")], tabs: ["Home"], taps: ["Account, delete": "erased"]),
            ]
        )

        let result = try Self.crawl(app)

        #expect(!app.hits.contains("Account, delete"))
        #expect(result.skipped.contains { $0.name == "Devices" && $0.reason == .couldNotReturn })
    }

    /// A screen that cannot be got back to has its remaining rows listed as such, never tapped elsewhere, and the verdict is qualified.
    @Test
    func aScreenTheCrawlCannotReturnToListsItsRemainingRowsAndQualifies() throws {
        let app = FakeDiscoveryApp(
            launch: "home",
            tabs: ["Home": "home"],
            screens: [
                "home": FakeDiscoveryApp.Screen(title: "Home", rows: ["Player", "Library"], tabs: ["Home"], taps: ["Player": "player", "Library": "library"]),
                "player": FakeDiscoveryApp.Screen(identifier: "player", texts: ["Now playing"]),
                "library": FakeDiscoveryApp.Screen(title: "Library", back: true, tabs: ["Home"]),
            ],
            afterRelaunch: ["home": FakeDiscoveryApp.Screen(title: "Welcome", texts: ["Sign in"], tabs: ["Home"])]
        )

        let result = try Self.crawl(app)

        #expect(!app.tapped.contains("Library"))
        #expect(result.skipped.contains { $0.name == "Library" && $0.reason == .couldNotReturn })
        #expect(result.answer(header: "discover", output: "draft.json").verdict.line.contains("1 control on a screen the crawl could not return to"))
    }

    /// A tab whose label slugs to `launch` takes another id, so the tabs filed under `launch` and its own controls are each listed once.
    @Test
    func aTabNamedLaunchDoesNotShareTheLaunchEntries() throws {
        let app = FakeDiscoveryApp(launch: "start", tabs: ["Launch": "start", "Other": "other"], screens: [
            "start": FakeDiscoveryApp.Screen(title: "Launch", controls: [(type: "Button", label: "Go")], tabs: ["Launch", "Launch ", "Other"]),
            "other": FakeDiscoveryApp.Screen(title: "Other", tabs: ["Launch", "Launch ", "Other"]),
        ])

        let result = try Self.crawl(app)

        #expect(result.walkbook.screens.map(\.id) == ["launch-2", "other"])
        #expect(result.skipped.count { $0.name == "Go" } == 1)
        #expect(result.lines().count { $0.hasPrefix("launch: ") } == 1)
    }

    /// A row below the fold whose `scrollTo` did not land was never tapped, so it says so rather than `tapped, did not land`.
    @Test
    func aRowThatCouldNotBeScrolledToIsListedAsSuchNotAsTapped() throws {
        let rows = (1 ... 16).map { "Row \(Character(UnicodeScalar(64 + $0) ?? "A"))" }
        let app = FakeDiscoveryApp(launch: "home", tabs: ["Home": "home"], screens: [
            "home": FakeDiscoveryApp.Screen(title: "Home", rows: rows, tabs: ["Home"], taps: ["Row P": "detail"]),
        ], unscrollable: ["Row P"])

        let result = try Self.crawl(app)

        #expect(!app.tapped.contains("Row P"))
        #expect(result.skipped.first { $0.name == "Row P" }?.reason == .couldNotScroll)
    }

    /// The same app state gives the same draft, byte for byte, and the draft is a walkbook `walk` loads.
    @Test
    func twoCrawlsOfOneAppGiveByteIdenticalDraftsThatLoad() throws {
        let first = try Self.crawl(Self.settingsLike()).encoded()
        let second = try Self.crawl(Self.settingsLike()).encoded()

        #expect(first == second)
        let loaded = try WalkbookLoader.load(from: first, source: "draft")
        #expect(loaded.screens.map(\.id) == ["settings", "general", "about", "privacy", "profile", "storage"])
        #expect(loaded.screens.allSatisfy { $0.states == [Walkbook.CaptureState(theme: .light)] })
        #expect(String(bytes: first, encoding: .utf8)?.hasSuffix("}\n") == true)
    }

    @Test
    func twoCrawlsOfALazyAppGiveByteIdenticalDrafts() throws {
        func draft() throws -> Data {
            try Self.crawl(Self.lazyApp(rows: ["First"] + Self.filler(20) + ["Last"], taps: ["First": "first-screen", "Last": "last-screen"])).encoded()
        }

        let first = try draft()

        #expect(try first == draft())
        #expect(try WalkbookLoader.load(from: first, source: "draft").screens.map(\.id) == ["hub", "first", "last"])
    }

    /// An id is the tapped label's slug; the parent's id goes before it when that slug is taken.
    @Test
    func aScreenIDIsTheTappedLabelsSlugWithTheParentsBreakingATie() throws {
        let app = FakeDiscoveryApp(launch: "root", screens: [
            "root": FakeDiscoveryApp.Screen(title: "Root", rows: ["Wi-Fi", "More"], taps: ["Wi-Fi": "wifi", "More": "more"]),
            "wifi": FakeDiscoveryApp.Screen(title: "Wi-Fi", back: true, texts: ["Networks"]),
            "more": FakeDiscoveryApp.Screen(title: "More", back: true, rows: ["Wi-Fi"], taps: ["Wi-Fi": "wifi-more"]),
            "wifi-more": FakeDiscoveryApp.Screen(title: "Wi-Fi", back: true, texts: ["Advanced"]),
        ])

        let result = try Self.crawl(app)

        #expect(result.walkbook.screens.map(\.id) == ["root", "wi-fi", "more", "more-wi-fi"])
    }

    /// `WalkbookLoader` refuses an empty route, so an app without tabs routes to its root by scrolling to the root's first row, as a hand-written Settings walkbook does.
    @Test
    func anAppWithoutTabsRoutesToItsRootByScrollingToItsFirstRow() throws {
        let app = FakeDiscoveryApp(launch: "root", screens: [
            "root": FakeDiscoveryApp.Screen(title: "Root", rows: ["General", "About"]),
        ])

        let result = try Self.crawl(app)

        #expect(result.walkbook.screens.map(\.route) == [[.scrollTo(label: "General")]])
        #expect(result.skipped.map(\.reason) == [.didNotLand, .didNotLand])
    }
}

extension DiscoverCrawlTests {
    static func crawl(_ app: FakeDiscoveryApp, depth: Int = 2, maxScreens: Int = 25) throws -> DiscoverResult {
        try DiscoverCrawl(appBundleID: "dev.simwalk.discover", state: Walkbook.CaptureState(theme: .light), depth: depth, maxScreens: maxScreens).run(on: app)
    }

    /// `count` plain rows named `<prefix> 1…`, which no tap lands on.
    static func filler(_ count: Int, prefix: String = "Filler") -> [String] {
        (1 ... count).map { "\(prefix) \($0)" }
    }

    /// An app whose one tab, Hub, is a lazy list of `rows`: those named in `taps` push a screen and the rest are filler.
    static func lazyApp(rows: [String], taps: [String: String], upFails: Set<String> = []) -> FakeDiscoveryApp {
        var screens = ["hub": FakeDiscoveryApp.Screen(title: "Hub", rows: rows, tabs: ["Hub"], table: true, taps: taps, plain: Set(rows.filter { taps[$0] == nil }), lazy: true)]
        for target in Set(taps.values) {
            screens[target] = FakeDiscoveryApp.Screen(title: target, back: true, tabs: ["Hub"])
        }
        return FakeDiscoveryApp(launch: "hub", tabs: ["Hub": "hub"], screens: screens, upFails: upFails)
    }

    /// Two tabs; a Settings tab with three rows and the controls a crawl must leave alone, a nested row, and a Profile tab.
    static func settingsLike() -> FakeDiscoveryApp {
        FakeDiscoveryApp(launch: "settings", tabs: ["Settings": "settings", "Profile": "profile"], screens: [
            "settings": FakeDiscoveryApp.Screen(
                title: "Settings",
                identifier: "settings-list",
                rows: ["General", "Privacy", "About"],
                controls: [(type: "Switch", label: "Airplane Mode"), (type: "Button", label: "Share"), (type: "TextField", label: "Name")],
                tabs: ["Settings", "Profile"],
                taps: ["General": "general", "Privacy": "privacy", "About": "about"]
            ),
            "general": FakeDiscoveryApp.Screen(title: "General", back: true, rows: ["About"], controls: [(type: "Button", label: "Erase All Content")], tabs: ["Settings", "Profile"], taps: ["About": "about"]),
            "privacy": FakeDiscoveryApp.Screen(title: "Privacy", identifier: "privacy", back: true, texts: ["Location"], tabs: ["Settings", "Profile"]),
            "about": FakeDiscoveryApp.Screen(title: "About", back: true, texts: ["Version 1"], tabs: ["Settings", "Profile"]),
            "profile": FakeDiscoveryApp.Screen(title: "Profile", rows: ["Storage"], tabs: ["Settings", "Profile"], taps: ["Storage": "storage"]),
            "storage": FakeDiscoveryApp.Screen(title: "Storage", back: true, texts: ["12 GB used"], tabs: ["Settings", "Profile"]),
        ])
    }
}
