//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// A remote sheet's content, missing from the tree read of every launch but the first after its host process started, found in the live hierarchy and put where the tree stops (SimWalk#48).
///
/// The live hierarchy scripted here is the one measured on HealthKit's sheet over an app's Progress screen, iOS 27.0, on a relaunch with `com.apple.HealthPrivacyService` alive: a window whose live children are a placeholder holding a copy of the host chain, the app's own screen (never in the snapshot), and the snapshot's own host screen, with an off-screen placeholder beside its chain.
struct RemoteContentGraftTests {
    private static let screen = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)
    private static let sheetBox = AXNode.Frame(x: 0, y: 0, width: 402, height: 812)
    private static let hostBox = AXNode.Frame(x: 0, y: 62, width: 402, height: 812)
    private static let offScreen = AXNode.Frame(x: -402, y: -874, width: 1206, height: 2622)
    private static let allCategory = AXNode(type: "Cell", frame: AXNode.Frame(x: 22, y: 341, width: 358, height: 52), identifier: "UIA.Health.AuthSheet.AllCategoryButton")

    /// The sheet's content as its root's own snapshot reports it, in the sheet's coordinates.
    private static let sheet = AXNode(type: "Other", frame: sheetBox, children: [
        AXNode(type: "StaticText", frame: AXNode.Frame(x: 20, y: 80, width: 362, height: 40), label: "Health Access"),
        AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 130, width: 402, height: 1)),
        AXNode(type: "Table", frame: AXNode.Frame(x: 0, y: 140, width: 402, height: 600), children: [allCategory]),
        AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: 750, width: 362, height: 50), label: "Allow", identifier: "UIA.Health.Allow.Button"),
    ])

    /// The app's own screen under the sheet, which the snapshot never holds; it has a `Allow` of its own.
    private static let progress = AXNode(type: "Other", frame: screen, children: [
        AXNode(type: "StaticText", frame: AXNode.Frame(x: 20, y: 100, width: 200, height: 30), label: "Progress"),
        AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: 700, width: 362, height: 50), label: "Allow"),
    ])

    /// The host's nesting: five `Other`s at the host's box, then `tail` at the sheet's.
    private static func hostChain(tail: Int = 3, content: AXNode? = nil) -> AXNode {
        var node = content ?? AXNode(type: "Other", frame: sheetBox)
        for _ in 1 ..< tail {
            node = AXNode(type: "Other", frame: sheetBox, children: [node])
        }
        for _ in 0 ..< 5 {
            node = AXNode(type: "Other", frame: hostBox, children: [node])
        }
        return node
    }

    /// `app.snapshot()` on a relaunch: the host screen, its off-screen leaf and its chain ending in a childless leaf where the sheet is hosted.
    private static func brokenTree() -> AXNode {
        AXNode(type: "Application", frame: screen, label: "RouteFixture", children: [
            AXNode(type: "Window", frame: screen, children: [
                AXNode(type: "Other", frame: screen, children: [AXNode(type: "Other", frame: offScreen), hostChain()]),
            ]),
        ])
    }

    /// `app.snapshot()` on the first launch after the host started: the sheet's content where the chain ends.
    private static func firstLaunchTree(content: AXNode = sheet) -> AXNode {
        AXNode(type: "Application", frame: screen, label: "RouteFixture", children: [
            AXNode(type: "Window", frame: screen, children: [
                AXNode(type: "Other", frame: screen, children: [AXNode(type: "Other", frame: offScreen), hostChain(content: content)]),
            ]),
        ])
    }

    /// The live hierarchy of either launch, as the runner's reads find it, with `before` ahead of everything else in the window.
    private static func live(sheet content: AXNode = sheet, before: [Live] = []) -> Live {
        // The copy of the host chain under the first placeholder: five links at the host's box, the fifth with
        // two live children — a placeholder over the remote root, and a two-link chain ending in nothing.
        let remoteRoot = Live(mirroring: content)
        let placeholder = Live(own: AXNode(type: "Other", frame: sheetBox), live: [remoteRoot])
        let deadEnd = Live(mirroring: AXNode(type: "Other", frame: sheetBox, children: [AXNode(type: "Other", frame: sheetBox)]))
        var link = Live(own: hostChain().children[0].children[0].children[0].children[0], live: [placeholder, deadEnd])
        for depth in (0 ..< 4).reversed() {
            var own = hostChain()
            for _ in 0 ..< depth {
                own = own.children[0]
            }
            link = Live(own: own, live: [link])
        }
        let copyHost = Live(own: AXNode(type: "Other", frame: screen), live: [link])
        let offScreenCopy = Live(own: AXNode(type: "Other", frame: offScreen), live: [Live(mirroring: hostChain())])
        let hostScreen = Live(own: brokenTree().children[0].children[0], live: [offScreenCopy, Live(mirroring: hostChain())])
        let window = Live(own: AXNode(type: "Window", frame: screen), live: before + [copyHost, Live(mirroring: progress), hostScreen])
        return Live(own: AXNode(type: "Application", frame: screen), live: [window])
    }

    /// The live hierarchy of a relaunch whose placeholder holds `content`, or is empty (`nil`) — content HealthKit has not put there yet, as `live(sheet:before:)` builds it but for the placeholder's count, with `before` ahead of everything else in the window.
    private static func live(placeholderHolding content: AXNode?, before: [Live] = []) -> Live {
        let placeholder = Live(own: AXNode(type: "Other", frame: sheetBox), live: content.map { [Live(mirroring: $0)] } ?? [])
        let deadEnd = Live(mirroring: AXNode(type: "Other", frame: sheetBox, children: [AXNode(type: "Other", frame: sheetBox)]))
        var link = Live(own: hostChain().children[0].children[0].children[0].children[0], live: [placeholder, deadEnd])
        for depth in (0 ..< 4).reversed() {
            var own = hostChain()
            for _ in 0 ..< depth {
                own = own.children[0]
            }
            link = Live(own: own, live: [link])
        }
        let copyHost = Live(own: AXNode(type: "Other", frame: screen), live: [link])
        let offScreenCopy = Live(own: AXNode(type: "Other", frame: offScreen), live: [Live(mirroring: hostChain())])
        let hostScreen = Live(own: brokenTree().children[0].children[0], live: [offScreenCopy, Live(mirroring: hostChain())])
        let window = Live(own: AXNode(type: "Window", frame: screen), live: before + [copyHost, Live(mirroring: progress), hostScreen])
        return Live(own: AXNode(type: "Application", frame: screen), live: [window])
    }

    /// **A relaunch's tree gets the sheet in place of the leaf the chain ends in**: once, in the sheet's own coordinates, and without the app's screen the live hierarchy also holds.
    @Test
    func aRelaunchGetsTheSheetWhereTheHostChainEnds() {
        let replayed = Self.replay(Self.brokenTree(), in: Self.live())

        #expect(replayed.tree == Self.firstLaunchTree())
        #expect(replayed.tree.flattened.count(where: { $0.identifier == Self.allCategory.identifier }) == 1)
        #expect(!replayed.tree.flattened.contains { $0.label == "Progress" })
        #expect(replayed.root == Array(repeating: 0, count: 9))
    }

    /// And the grafted control is one `systemTap` admits, judged against its own snapshot's frame as the runner judges it.
    @Test
    func theGraftedControlIsAdmittedByItsOwnSnapshotFrame() {
        let replayed = Self.replay(Self.brokenTree(), in: Self.live())

        #expect(SystemSheetScope.admittingAll(of: Self.brokenTree()).admits(Self.allCategory, in: replayed.tree))
        #expect(!SystemSheetScope.admittingAll(of: Self.brokenTree()).admits(Self.allCategory, in: Self.brokenTree()))
    }

    /// **A first launch's tree already holds the sheet**, so it is left as it was read — never the sheet twice — and the root's path still comes back for the next read.
    @Test
    func aFirstLaunchTreeIsLeftAsItWasRead() {
        let replayed = Self.replay(Self.firstLaunchTree(), in: Self.live())

        #expect(replayed.tree == Self.firstLaunchTree())
        #expect(replayed.root == Array(repeating: 0, count: 9))
    }

    /// **A known root is read first, and alone**: one live read for every tree read after the first in a step.
    @Test
    func aKnownRootIsReadAloneAndGrafted() {
        let root = Array(repeating: 0, count: 9)

        let replayed = Self.replay(Self.brokenTree(), in: Self.live(), recall: .root(root))

        #expect(replayed.requests == [.read(root, known: true)])
        #expect(replayed.tree == Self.firstLaunchTree())
        #expect(replayed.root == root)
    }

    /// A known root that is no longer a sheet's content — gone, or a link of the host chain now at its path — sends the walk back to the gate.
    @Test(arguments: [[0, 0, 0], [0, 7]])
    func aKnownRootThatMovedIsWalkedForAgain(root: [Int]) {
        let replayed = Self.replay(Self.brokenTree(), in: Self.live(), recall: .root(root))

        #expect(replayed.requests.prefix(3) == [.read(root, known: true), .countDescendants, .countChildren([])])
        #expect(replayed.tree == Self.firstLaunchTree())
    }

    /// **A known root whose path now names other content is walked for again** (SimWalk#56): a live reshuffle can put a branching element at the root's old path — here the app's own screen — which has no place in the tree, so it is neither kept nor grafted, and the walk finds the sheet.
    @Test
    func aKnownRootNamingOtherContentIsWalkedForAgain() {
        let replayed = Self.replay(Self.brokenTree(), in: Self.live(), recall: .root([0, 1]))

        #expect(replayed.requests.prefix(2) == [.read([0, 1], known: true), .countDescendants])
        #expect(replayed.tree == Self.firstLaunchTree())
        #expect(replayed.root == Array(repeating: 0, count: 9))
    }

    /// **A plain screen pays one count.** Childless anonymous leaves are common, so the gate is the live count: no more descendants than the tree has nodes, and nothing is walked.
    @Test
    func aPlainScreenWithAnonymousLeavesPaysOneCount() {
        let plain = AXNode(type: "Application", frame: Self.screen, children: [
            AXNode(type: "Window", frame: Self.screen, children: [
                AXNode(type: "Other", frame: Self.screen, children: [AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 100)), Self.progress]),
            ]),
        ])

        let replayed = Self.replay(plain, in: Live(mirroring: plain))

        #expect(replayed.requests == [.countDescendants])
        #expect(replayed.tree == plain)
    }

    /// A tree with nowhere to graft to — no on-screen childless anonymous leaf — is answered without a single live read.
    @Test
    func aTreeWithNoGraftSiteCostsNoRead() {
        let tree = AXNode(type: "Application", frame: Self.screen, children: [
            AXNode(type: "Window", frame: Self.screen, children: [AXNode(type: "Other", frame: Self.offScreen), Self.progress]),
        ])

        let replayed = Self.replay(tree, in: Self.live())

        #expect(replayed.requests.isEmpty)
        #expect(replayed.tree == tree)
    }

    /// The walk is bounded in live queries: a hierarchy deeper than the limit is left as it was read, having cost no more than it (SimWalk#57).
    @Test
    func theWalkStopsAtItsReadLimit() {
        let replayed = Self.replay(Self.brokenTree(), in: Self.live(), readLimit: 6)

        #expect(replayed.queries <= 6)
        #expect(replayed.tree == Self.brokenTree())
        #expect(replayed.root == nil)
    }

    /// **The limit counts queries, not requests** (SimWalk#57): a known root's read asks `exists` before its snapshot, so a root gone since leaves one query of three for the count that gates the walk, and none for the walk.
    @Test
    func aKnownRootsReadIsChargedItsExists() {
        let replayed = Self.replay(Self.brokenTree(), in: Self.live(), recall: .root([0, 7]), readLimit: 3)

        #expect(replayed.requests == [.read([0, 7], known: true), .countDescendants])
        #expect(replayed.queries == 3)
        #expect(replayed.tree == Self.brokenTree())
    }

    /// A count below the app asks `exists` first, so it is charged two: with one query left after the app's own count, the window is not counted (SimWalk#57).
    @Test
    func aCountBelowTheAppIsChargedItsExists() {
        let replayed = Self.replay(Self.brokenTree(), in: Self.live(), readLimit: 3)

        #expect(replayed.requests == [.countDescendants, .countChildren([])])
        #expect(replayed.queries == 2)
    }

    /// An element gone between its parent's count and its own read is passed over, and the walk goes on to its siblings.
    @Test
    func anElementGoneBeforeItsReadIsPassedOver() {
        var live = Self.live()
        live.live[0].live.insert(Live(own: AXNode(type: "Other", frame: Self.screen), live: [], gone: true), at: 0)

        let replayed = Self.replay(Self.brokenTree(), in: live)

        #expect(replayed.tree == Self.firstLaunchTree())
        #expect(replayed.root == [0, 1] + Array(repeating: 0, count: 7))
    }

    /// **A known root is read for its snapshot alone** — never its live children, which a vanished element answers with a recorded test failure — whatever is at its path now: the root, a host-chain link, a placeholder, or nothing; a moved one is walked for again from the gate.
    @Test(arguments: [Array(repeating: 0, count: 9), [0, 0, 0], [0, 0], [0, 7]])
    func aKnownRootIsNeverCounted(root: [Int]) {
        let replayed = Self.replay(Self.brokenTree(), in: Self.live(), recall: .root(root))

        // Next is the graft's answer, or the gate a moved root sends the walk back to: never the root's count.
        #expect(replayed.requests.first == .read(root, known: true))
        #expect([nil, .countDescendants].contains(replayed.requests.dropFirst().first))
    }

    /// The walk counts only what it passes through — the app, the window, placeholders and host-chain links — and reads the remote root without a count.
    @Test
    func theWalkCountsOnlyWhatItPassesThrough() {
        let replayed = Self.replay(Self.brokenTree(), in: Self.live())

        let counted = replayed.requests.compactMap { step -> [Int]? in
            guard case let .countChildren(path) = step else { return nil }
            return path
        }

        #expect(counted == (0 ... 8).map { Array(repeating: 0, count: $0) })
    }

    /// A walk's reads are of elements it has just counted, so none asks whether its element still exists: only a known root, found by an earlier tree read, does.
    @Test
    func noWalkReadIsOfAKnownRoot() {
        let replayed = Self.replay(Self.brokenTree(), in: Self.live())

        let known = replayed.requests.filter { step in
            guard case let .read(_, known) = step else { return false }
            return known
        }

        #expect(known.isEmpty)
        #expect(replayed.requests.contains(.read(Array(repeating: 0, count: 9), known: false)))
    }

    /// **A first launch's sheet holding a childless anonymous `Other` at its own box is not grafted into itself**: the tree already holds the content, so it comes back as read, every control on the sheet once.
    @Test
    func aFirstLaunchSheetIsNotGraftedIntoItself() {
        let backed = AXNode(type: "Other", frame: Self.sheetBox, children: Self.sheet.children + [AXNode(type: "Other", frame: Self.sheetBox)])

        let replayed = Self.replay(Self.firstLaunchTree(content: backed), in: Self.live(sheet: backed))

        #expect(replayed.tree == Self.firstLaunchTree(content: backed))
        #expect(replayed.tree.flattened.count(where: { $0.identifier == "UIA.Health.Allow.Button" }) == 1)
    }

    /// **A candidate with no place in the tree is passed over**: a copy of the sheet under an earlier placeholder, in the host's coordinates, matches no graft site, and the walk goes on to the real root.
    @Test
    func aCandidateWithNoPlaceInTheTreeIsPassedOver() {
        let copy = AXNode(type: "Other", frame: Self.hostBox, children: Self.sheet.children)
        let earlier = Live(own: AXNode(type: "Other", frame: Self.screen), live: [Live(mirroring: copy)])

        let replayed = Self.replay(Self.brokenTree(), in: Self.live(before: [earlier]))

        #expect(replayed.tree == Self.firstLaunchTree())
        #expect(replayed.root == [0, 1] + Array(repeating: 0, count: 7))
    }

    /// **Only content under a placeholder is a candidate**: the app's own hidden screen, first in the window and at the sheet's own type and box, is passed over, and the sheet is grafted rather than the screen.
    @Test
    func theAppsOwnScreenIsNeverGrafted() {
        let hidden = AXNode(type: "Other", frame: Self.sheetBox, children: Self.progress.children)

        let replayed = Self.replay(Self.brokenTree(), in: Self.live(before: [Live(mirroring: hidden)]))

        #expect(replayed.tree == Self.firstLaunchTree())
        #expect(!replayed.tree.flattened.contains { $0.label == "Progress" })
    }

    /// Of two graft sites at the sheet's box, the sheet goes into the last in tree order — the one drawn in front — and only there.
    @Test
    func theFrontmostOfTwoSitesGetsTheSheet() {
        let hostScreen = { (chains: [AXNode]) in
            AXNode(type: "Application", frame: Self.screen, label: "RouteFixture", children: [
                AXNode(type: "Window", frame: Self.screen, children: [
                    AXNode(type: "Other", frame: Self.screen, children: [AXNode(type: "Other", frame: Self.offScreen)] + chains),
                ]),
            ])
        }

        let replayed = Self.replay(hostScreen([Self.hostChain(), Self.hostChain()]), in: Self.live())

        #expect(replayed.tree == hostScreen([Self.hostChain(), Self.hostChain(content: Self.sheet)]))
    }

    /// **A sheet that fills the screen is still grafted** (SimWalk#57): its box is the host screen's, a branching anonymous `Other` in the relaunch tree, and only the sheet's own controls say whether the tree holds it.
    @Test
    func aSheetFillingTheScreenIsGraftedOverTheHostScreenAtItsBox() {
        let fullScreen = AXNode(type: "Other", frame: Self.screen, children: Self.sheet.children)
        let relaunch = { (end: AXNode) in
            AXNode(type: "Application", frame: Self.screen, label: "RouteFixture", children: [
                AXNode(type: "Window", frame: Self.screen, children: [
                    AXNode(type: "Other", frame: Self.screen, children: [
                        AXNode(type: "Other", frame: Self.offScreen),
                        AXNode(type: "Other", frame: Self.screen, children: [end]),
                    ]),
                ]),
            ])
        }
        let broken = relaunch(AXNode(type: "Other", frame: Self.screen))
        let placeholder = Live(own: AXNode(type: "Other", frame: Self.screen), live: [Live(mirroring: fullScreen)])
        let window = Live(own: AXNode(type: "Window", frame: Self.screen), live: [placeholder, Live(mirroring: broken.children[0].children[0])])

        let replayed = Self.replay(broken, in: Live(own: AXNode(type: "Application", frame: Self.screen), live: [window]))

        #expect(replayed.tree == relaunch(fullScreen))
        #expect(replayed.root == [0, 0, 0])
    }

    /// **A walk that found nothing is not made again for a tree of the same shape** (SimWalk#56): a screen that passes the gate with no remote root pays its walk once per step, not on every settle and dismissal poll — a changed label is the same shape, and a changed shape is walked again.
    @Test
    func aWalkThatFoundNothingIsNotRepeatedForTheSameShape() {
        let hostScreen = Self.brokenTree().children[0].children[0]
        let noSheet = Live(own: AXNode(type: "Application", frame: Self.screen), live: [
            Live(own: AXNode(type: "Window", frame: Self.screen), live: [Live(mirroring: Self.progress), Live(mirroring: hostScreen)]),
        ])
        var relabelled = Self.brokenTree()
        relabelled.label = "RouteFixture, updated"
        let deeper = { (content: AXNode?) in
            AXNode(type: "Application", frame: Self.screen, label: "RouteFixture", children: [
                AXNode(type: "Window", frame: Self.screen, children: [
                    AXNode(type: "Other", frame: Self.screen, children: [AXNode(type: "Other", frame: Self.offScreen), Self.hostChain(tail: 4, content: content)]),
                ]),
            ])
        }

        let walked = Self.replay(Self.brokenTree(), in: noSheet)
        let again = Self.replay(relabelled, in: noSheet, recall: walked.recall)
        let changed = Self.replay(deeper(nil), in: Self.live(), recall: walked.recall)

        #expect(walked.requests.count > 1)
        #expect(walked.root == nil)
        #expect(again.requests.isEmpty)
        #expect(again.recall == walked.recall)
        #expect(changed.requests.first == .countDescendants)
        #expect(changed.tree == deeper(Self.sheet))
    }

    /// **A host placeholder with zero live children is walked again on the next read** (SimWalk#56): the gate found nowhere to graft because HealthKit had not put the sheet's content there yet, so that outcome is not remembered against the tree's shape — a later read, with the content now under the placeholder, grafts it.
    @Test
    func aHostPlaceholderWithZeroLiveChildrenIsWalkedAgainOnTheNextRead() {
        let tree = Self.brokenTree()
        let first = Self.replay(tree, in: Self.live(placeholderHolding: nil))
        let second = Self.replay(tree, in: Self.live(placeholderHolding: Self.sheet), recall: first.recall)

        #expect(first.root == nil)
        #expect(first.recall == .emptyPlaceholder(RemoteContentGraft.Shape(of: tree), descendants: Self.live(placeholderHolding: nil).descendants, held: 0))
        #expect(second.requests.first == .countDescendants)
        #expect(second.root != nil)
    }

    /// **A placeholder still empty on the next read costs one live query, not the walk** (SimWalk#84): the walk that ended at it is remembered with the app's live descendant count, and a read of the same shape with that count unchanged asks nothing more — where the walk itself was ten.
    @Test
    func aPlaceholderStillEmptyOnTheNextReadCostsOneCount() {
        let tree = Self.brokenTree()
        let empty = Self.live(placeholderHolding: nil)
        let first = Self.replay(tree, in: empty)
        let again = Self.replay(tree, in: empty, recall: first.recall)

        #expect(first.queries > 1)
        #expect(again.requests == [.countDescendants])
        #expect(again.queries == 1)
        #expect(again.recall == .emptyPlaceholder(RemoteContentGraft.Shape(of: tree), descendants: empty.descendants, held: 1))
        #expect(again.tree == tree)
    }

    /// **Content that arrives after the empty placeholder was remembered is still grafted** (SimWalk#84): the remembered count is the empty placeholder's, the content's arrival raises it, and the read that sees it walks again — however many reads found the placeholder empty first.
    @Test
    func contentArrivingUnderARememberedEmptyPlaceholderIsGrafted() {
        let tree = Self.brokenTree()
        let empty = Self.live(placeholderHolding: nil)
        let first = Self.replay(tree, in: empty)
        let again = Self.replay(tree, in: empty, recall: first.recall)
        let arrived = Self.replay(tree, in: Self.live(placeholderHolding: Self.sheet), recall: again.recall)

        #expect(arrived.requests.first == .countDescendants)
        #expect(arrived.root != nil)
        #expect(arrived.tree == Self.firstLaunchTree())
    }

    /// **A first launch whose table moved between its two reads still holds the sheet** (SimWalk#58): by the root's own snapshot, read after `app.snapshot()`, the decelerating table has scrolled — a row moved, a row turned from `StaticText` into a `Button`, a row came into view — and the tree is left as it was read, never the sheet grafted into its own in-sheet site, every control on it twice.
    @Test
    func aFirstLaunchSheetWhoseTableMovedBetweenReadsIsHeld() {
        let sheet = { (rows: [AXNode]) in
            AXNode(type: "Other", frame: Self.sheetBox, children: [
                Self.sheet.children[0],
                Self.sheet.children[1],
                AXNode(type: "Table", frame: AXNode.Frame(x: 0, y: 140, width: 402, height: 600), children: rows),
                Self.sheet.children[3],
                AXNode(type: "Other", frame: Self.sheetBox),
            ])
        }
        let row = { (type: String, y: Double, label: String) in
            AXNode(type: type, frame: AXNode.Frame(x: 22, y: y, width: 358, height: 44), label: label)
        }
        let moved = AXNode(type: "Cell", frame: AXNode.Frame(x: 22, y: 317, width: 358, height: 52), identifier: Self.allCategory.identifier)
        let read = sheet([Self.allCategory, row("StaticText", 400, "Steps")])
        let snapshot = sheet([moved, row("Button", 376, "Steps"), row("Button", 424, "Heart Rate")])

        let replayed = Self.replay(Self.firstLaunchTree(content: read), in: Self.live(sheet: snapshot))

        #expect(replayed.tree == Self.firstLaunchTree(content: read))
        #expect(replayed.tree.flattened.count(where: { $0.identifier == "UIA.Health.Allow.Button" }) == 1)
    }

    /// **A relaunch is grafted even where the app's own screen shares a label with the sheet** (SimWalk#58): one of the sheet's three labelled and identified nodes found in the tree is no majority, so the sheet goes in where the host chain ends.
    @Test
    func aRelaunchWhoseScreenSharesALabelWithTheSheetIsGrafted() {
        let screen = AXNode(type: "Other", frame: Self.screen, children: [
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 20, y: 300, width: 200, height: 30), label: "Health Access"),
        ])
        let relaunch = { (chain: AXNode) in
            AXNode(type: "Application", frame: Self.screen, label: "RouteFixture", children: [
                AXNode(type: "Window", frame: Self.screen, children: [
                    screen,
                    AXNode(type: "Other", frame: Self.screen, children: [AXNode(type: "Other", frame: Self.offScreen), chain]),
                ]),
            ])
        }

        let replayed = Self.replay(relaunch(Self.hostChain()), in: Self.live(before: [Live(mirroring: screen)]))

        #expect(replayed.tree == relaunch(Self.hostChain(content: Self.sheet)))
        #expect(replayed.tree.flattened.count(where: { $0.identifier == Self.allCategory.identifier }) == 1)
    }

    /// **A small sheet over a screen sharing most of its labels is still grafted on a relaunch** (SimWalk#61 item 1): the app's own `Allow` / `Don't Allow` primer matches two of the sheet's three nodes by label, a majority, but none at the sheet's own box, so the sheet goes in where the host chain ends rather than reading as held — under an `atLaunch` step that would be a tap on the app's `Allow`, under the sheet.
    @Test
    func aRelaunchWhosePrimerSharesMostOfASmallSheetsLabelsIsGrafted() {
        let button = { (label: String, y: Double) in
            AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: y, width: 362, height: 50), label: label)
        }
        let small = AXNode(type: "Other", frame: Self.sheetBox, children: [
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 20, y: 80, width: 362, height: 40), label: "Health Access"),
            button("Don't Allow", 690),
            button("Allow", 750),
        ])
        let primer = AXNode(type: "Other", frame: Self.screen, children: [button("Don't Allow", 600), button("Allow", 660)])
        let relaunch = { (chain: AXNode) in
            AXNode(type: "Application", frame: Self.screen, label: "RouteFixture", children: [
                AXNode(type: "Window", frame: Self.screen, children: [
                    primer,
                    AXNode(type: "Other", frame: Self.screen, children: [AXNode(type: "Other", frame: Self.offScreen), chain]),
                ]),
            ])
        }

        let replayed = Self.replay(relaunch(Self.hostChain()), in: Self.live(sheet: small, before: [Live(mirroring: primer)]))

        #expect(replayed.tree == relaunch(Self.hostChain(content: small)))
    }

    /// **One node at its own box is not a majority** (SimWalk#61): a relaunch whose screen has an `Allow` exactly where the sheet's `Allow` will be matches one of the sheet's two fixed nodes, anchored, and the sheet is still grafted where the host chain ends.
    @Test
    func aRelaunchSharingOneNodeAtItsOwnBoxIsGrafted() {
        let screen = AXNode(type: "Other", frame: Self.screen, children: [Self.sheet.children[3]])
        let relaunch = { (chain: AXNode) in
            AXNode(type: "Application", frame: Self.screen, label: "RouteFixture", children: [
                AXNode(type: "Window", frame: Self.screen, children: [
                    screen,
                    AXNode(type: "Other", frame: Self.screen, children: [AXNode(type: "Other", frame: Self.offScreen), chain]),
                ]),
            ])
        }

        let replayed = Self.replay(relaunch(Self.hostChain()), in: Self.live(before: [Live(mirroring: screen)]))

        #expect(replayed.tree == relaunch(Self.hostChain(content: Self.sheet)))
    }

    /// **Content whose every node scrolls is held by its labels alone** (SimWalk#61): with no node outside a table to be found at its own box, a first launch whose rows all moved between the reads still holds the sheet, every row once.
    @Test
    func aFirstLaunchSheetThatIsAllTableIsHeldByItsLabels() {
        let sheet = { (top: Double) in
            AXNode(type: "Other", frame: Self.sheetBox, children: [
                AXNode(type: "Table", frame: Self.sheetBox, children: ["Steps", "Heart Rate", "Sleep"].enumerated().map { index, label in
                    AXNode(type: "Cell", frame: AXNode.Frame(x: 22, y: top + 52 * Double(index), width: 358, height: 44), label: label)
                }),
                AXNode(type: "Other", frame: Self.sheetBox),
            ])
        }

        let replayed = Self.replay(Self.firstLaunchTree(content: sheet(150)), in: Self.live(sheet: sheet(120)))

        #expect(replayed.tree == Self.firstLaunchTree(content: sheet(150)))
        #expect(replayed.tree.flattened.count(where: { $0.label == "Steps" }) == 1)
    }

    /// **A first launch whose table scrolled far between its two reads still holds the sheet** (SimWalk#61 item 2): every row in the snapshot is one the tree never read, and they outnumber the sheet's fixed nodes, and its large title moved as the table scrolled — but the nodes outside the table are all found, `Allow` at its own box, so the tree is left as it was read, never the sheet grafted into its own in-sheet site.
    @Test
    func aFirstLaunchSheetWhoseTableScrolledFarBetweenReadsIsHeld() {
        let sheet = { (titleY: Double, rows: [String]) in
            AXNode(type: "Other", frame: Self.sheetBox, children: [
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 20, y: titleY, width: 362, height: 40), label: "Health Access"),
                AXNode(type: "Table", frame: AXNode.Frame(x: 0, y: 140, width: 402, height: 600), children: rows.enumerated().map { index, label in
                    AXNode(type: "Cell", frame: AXNode.Frame(x: 22, y: 150 + 52 * Double(index), width: 358, height: 44), label: label)
                }),
                Self.sheet.children[3],
                AXNode(type: "Other", frame: Self.sheetBox),
            ])
        }
        let read = sheet(80, ["Steps", "Heart Rate", "Sleep", "Weight", "Workouts"])
        let snapshot = sheet(60, ["Cycling", "Rowing", "Swimming", "Walking", "Running"])

        let replayed = Self.replay(Self.firstLaunchTree(content: read), in: Self.live(sheet: snapshot))

        #expect(replayed.tree == Self.firstLaunchTree(content: read))
        #expect(replayed.tree.flattened.count(where: { $0.identifier == "UIA.Health.Allow.Button" }) == 1)
    }

    /// **A primer whose controls sit at the sheet's own boxes is not the sheet** (SimWalk#78 item 1): on a relaunch, the app's `Allow` / `Don't Allow` primer has both buttons exactly where a HealthKit-sized sheet's are, two of its three fixed nodes and both at their boxes, but not the sheet's title, so the sheet goes in where the host chain ends rather than reading as held.
    @Test
    func aRelaunchWhosePrimerSitsAtTheSheetsBoxesIsGrafted() {
        let button = { (label: String, y: Double) in
            AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: y, width: 362, height: 50), label: label)
        }
        let rows = ["Turn On All", "Steps", "Heart Rate", "Sleep", "Weight"].enumerated().map { index, label in
            AXNode(type: "Cell", frame: AXNode.Frame(x: 22, y: 150 + 52 * Double(index), width: 358, height: 44), label: label)
        }
        let healthKit = AXNode(type: "Other", frame: Self.sheetBox, children: [
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 20, y: 80, width: 362, height: 40), label: "Health Access"),
            AXNode(type: "Table", frame: AXNode.Frame(x: 0, y: 140, width: 402, height: 540), children: rows),
            button("Don't Allow", 690),
            button("Allow", 750),
        ])
        let primer = AXNode(type: "Other", frame: Self.sheetBox, children: [button("Don't Allow", 690), button("Allow", 750)])
        let relaunch = { (chain: AXNode) in
            AXNode(type: "Application", frame: Self.screen, label: "RouteFixture", children: [
                AXNode(type: "Window", frame: Self.screen, children: [
                    primer,
                    AXNode(type: "Other", frame: Self.screen, children: [AXNode(type: "Other", frame: Self.offScreen), chain]),
                ]),
            ])
        }

        let replayed = Self.replay(relaunch(Self.hostChain()), in: Self.live(sheet: healthKit, before: [Live(mirroring: primer)]))

        #expect(replayed.tree == relaunch(Self.hostChain(content: healthKit)))
    }

    /// **A sheet whose only fixed node is a large title that collapsed between its two reads is still held** (SimWalk#78 item 2): the title is found by its label but not at its box, and most of the sheet's nodes, its rows included, are found by label, so the tree is left as it was read, never the sheet grafted into its own in-sheet site.
    @Test
    func aFirstLaunchSheetWhoseOnlyFixedNodeIsACollapsingTitleIsHeld() {
        let read = Self.titledTable(titleY: 80, top: 150, ["Steps", "Heart Rate", "Sleep", "Weight"])
        let snapshot = Self.titledTable(titleY: 60, top: 130, ["Heart Rate", "Sleep", "Weight", "Workouts"])

        let replayed = Self.replay(Self.firstLaunchTree(content: read), in: Self.live(sheet: snapshot))

        #expect(replayed.tree == Self.firstLaunchTree(content: read))
        #expect(replayed.tree.flattened.count(where: { $0.label == "Heart Rate" }) == 1)
    }

    /// **But a relaunch's screen sharing that title alone is not the sheet** (SimWalk#78 item 2): the title is the sheet's one fixed node and is found, not at its box, and none of the rows is, so the sheet goes in where the host chain ends.
    @Test
    func aRelaunchSharingOnlyTheTitleOfATitledTableIsGrafted() {
        let titled = Self.titledTable(titleY: 80, top: 150, ["Steps", "Heart Rate", "Sleep", "Weight"])
        let screen = AXNode(type: "Other", frame: Self.screen, children: [
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 20, y: 300, width: 200, height: 30), label: "Health Access"),
        ])
        let relaunch = { (chain: AXNode) in
            AXNode(type: "Application", frame: Self.screen, label: "RouteFixture", children: [
                AXNode(type: "Window", frame: Self.screen, children: [
                    screen,
                    AXNode(type: "Other", frame: Self.screen, children: [AXNode(type: "Other", frame: Self.offScreen), chain]),
                ]),
            ])
        }

        let replayed = Self.replay(relaunch(Self.hostChain()), in: Self.live(sheet: titled, before: [Live(mirroring: screen)]))

        #expect(replayed.tree == relaunch(Self.hostChain(content: titled)))
    }

    /// **A primer carrying every label of the sheet, at its own boxes, is not the sheet** (SimWalk#78 round 2): on a relaunch, the app's full-screen primer shows the sheet's title, two of its rows, `Don't Allow` and `Allow` — every node of the sheet outside its table and five of its six nodes — but none at the sheet's boxes and its list in a table of its own box, so the sheet goes in where the host chain ends rather than reading as held and leaving an `atLaunch` step to tap the app's `Allow` under it.
    @Test
    func aRelaunchWhosePrimerCarriesEverySheetLabelIsGrafted() {
        let button = { (label: String, y: Double) in
            AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: y, width: 362, height: 50), label: label)
        }
        let rows = { (top: Double, labels: [String]) in
            labels.enumerated().map { index, label in
                AXNode(type: "Cell", frame: AXNode.Frame(x: 22, y: top + 52 * Double(index), width: 358, height: 44), label: label)
            }
        }
        let labelled = AXNode(type: "Other", frame: Self.sheetBox, children: [
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 20, y: 80, width: 362, height: 40), label: "Health Access"),
            AXNode(type: "Table", frame: AXNode.Frame(x: 0, y: 140, width: 402, height: 540), children: rows(150, ["Steps", "Heart Rate", "Sleep"])),
            button("Don't Allow", 690),
            button("Allow", 750),
        ])
        let primer = AXNode(type: "Other", frame: Self.screen, children: [
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 20, y: 120, width: 362, height: 40), label: "Health Access"),
            AXNode(type: "Table", frame: AXNode.Frame(x: 0, y: 200, width: 402, height: 300), children: rows(210, ["Steps", "Heart Rate"])),
            button("Don't Allow", 620),
            button("Allow", 690),
        ])
        let relaunch = { (chain: AXNode) in
            AXNode(type: "Application", frame: Self.screen, label: "RouteFixture", children: [
                AXNode(type: "Window", frame: Self.screen, children: [
                    primer,
                    AXNode(type: "Other", frame: Self.screen, children: [AXNode(type: "Other", frame: Self.offScreen), chain]),
                ]),
            ])
        }

        let replayed = Self.replay(relaunch(Self.hostChain()), in: Self.live(sheet: labelled, before: [Live(mirroring: primer)]))

        #expect(replayed.tree == relaunch(Self.hostChain(content: labelled)))
        #expect(replayed.tree.flattened.count(where: { $0.label == "Sleep" }) == 1)
    }

    /// **A sheet whose only fixed node is a collapsing title is held even when its table scrolled far between the reads** (SimWalk#78 round 2): no row of the snapshot is one the tree read and the title moved, so nothing labelled is at its box, but the table is, and the tree is left as it was read, never the sheet grafted into its own in-sheet site.
    @Test
    func aFirstLaunchTitledTableThatScrolledFarBetweenReadsIsHeld() {
        let read = Self.titledTable(titleY: 80, top: 150, ["Steps", "Heart Rate", "Sleep", "Weight", "Workouts"])
        let snapshot = Self.titledTable(titleY: 60, top: 130, ["Cycling", "Rowing", "Swimming", "Walking", "Running"])

        let replayed = Self.replay(Self.firstLaunchTree(content: read), in: Self.live(sheet: snapshot))

        #expect(replayed.tree == Self.firstLaunchTree(content: read))
        #expect(replayed.tree.flattened.count(where: { $0.label == "Health Access" }) == 1)
    }

    /// **A walk that passed over a candidate is not remembered as an empty placeholder** (SimWalk#84): a copy of the sheet in the host's coordinates, under a placeholder of its own, has no place in the tree, and the on-screen placeholder is empty.
    ///
    /// The host can move that content under a site with the app's live count unchanged, so the next read of the same shape walks again and grafts it.
    @Test
    func aWalkThatPassedOverACandidateIsWalkedAgainAtTheSameCount() {
        let tree = Self.brokenTree()
        let copy = AXNode(type: "Other", frame: Self.hostBox, children: Self.sheet.children)
        let elsewhere = Self.live(placeholderHolding: nil, before: [Live(own: AXNode(type: "Other", frame: Self.screen), live: [Live(mirroring: copy)])])
        let moved = Self.live(placeholderHolding: Self.sheet, before: [Live(own: AXNode(type: "Other", frame: Self.screen), live: [])])

        let first = Self.replay(tree, in: elsewhere)
        let second = Self.replay(tree, in: moved, recall: first.recall)

        #expect(elsewhere.descendants == moved.descendants)
        #expect(first.recall == .unknown)
        #expect(second.tree == Self.firstLaunchTree())
    }

    /// **A remembered empty placeholder is walked again in full every `rewalkEvery`-th read** (SimWalk#84): content arriving just as as many of the app's own elements go leaves the live count where it was, and the count alone would hide it for the rest of the step.
    ///
    /// The reads before it cost one count each; the one that walks grafts.
    @Test
    func anEmptyPlaceholderWhoseCountHeldWhileContentArrivedIsWalkedOnTheKthRead() {
        let tree = Self.brokenTree()
        let filler = AXNode(type: "Other", frame: Self.screen, label: "Filler", children: Array(
            repeating: AXNode(type: "StaticText", frame: Self.screen, label: "Row"),
            count: Live(mirroring: Self.sheet).descendants
        ))
        let empty = Self.live(placeholderHolding: nil, before: [Live(mirroring: filler)])
        let arrived = Self.live(placeholderHolding: Self.sheet)
        var reads = [Self.replay(tree, in: empty)]
        for _ in 1 ... RemoteContentGraft.rewalkEvery {
            reads.append(Self.replay(tree, in: arrived, recall: reads[reads.count - 1].recall))
        }

        #expect(empty.descendants == arrived.descendants)
        #expect(reads[1 ..< RemoteContentGraft.rewalkEvery].allSatisfy { $0.requests == [.countDescendants] && $0.tree == tree })
        #expect(reads[RemoteContentGraft.rewalkEvery].tree == Self.firstLaunchTree())
    }

    /// **A remembered empty placeholder is walked again for a tree of another shape** (SimWalk#84): the live count is the same, but it was the count of another tree's walk.
    @Test
    func aRememberedEmptyPlaceholderIsWalkedAgainForAChangedShape() {
        let empty = Self.live(placeholderHolding: nil)
        let deeper = AXNode(type: "Application", frame: Self.screen, label: "RouteFixture", children: [
            AXNode(type: "Window", frame: Self.screen, children: [
                AXNode(type: "Other", frame: Self.screen, children: [AXNode(type: "Other", frame: Self.offScreen), Self.hostChain(tail: 4)]),
            ]),
        ])

        let first = Self.replay(Self.brokenTree(), in: empty)
        let changed = Self.replay(deeper, in: empty, recall: first.recall)

        #expect(RemoteContentGraft.Shape(of: deeper) != RemoteContentGraft.Shape(of: Self.brokenTree()))
        #expect(changed.requests.count > 1)
        #expect(changed.recall == .emptyPlaceholder(RemoteContentGraft.Shape(of: deeper), descendants: empty.descendants, held: 0))
    }

    /// **A walk that passed over a candidate is not remembered as walked for nothing** (SimWalk#86): the sheet under a placeholder at the host's box has no site of its frame, no placeholder is empty, and the host then moves it to the site's frame with the tree's shape and the app's live count unchanged.
    ///
    /// The next read of the same shape walks again and grafts it, where a remembered `.noRoot` would leave the control on screen and ungrafted for the rest of the step.
    @Test
    func aSheetPassedOverAtAnotherFrameIsGraftedOnceItIsAtTheSites() {
        let tree = Self.brokenTree()
        let hierarchy = { (content: AXNode) in
            let placeholder = Live(own: AXNode(type: "Other", frame: Self.sheetBox), live: [Live(mirroring: content)])
            let window = Live(own: AXNode(type: "Window", frame: Self.screen), live: [placeholder, Live(mirroring: Self.progress), Live(mirroring: tree.children[0].children[0])])
            return Live(own: AXNode(type: "Application", frame: Self.screen), live: [window])
        }
        let elsewhere = hierarchy(AXNode(type: "Other", frame: Self.hostBox, children: Self.sheet.children))
        let atSite = hierarchy(Self.sheet)

        let first = Self.replay(tree, in: elsewhere)
        let second = Self.replay(tree, in: atSite, recall: first.recall)

        #expect(elsewhere.descendants == atSite.descendants)
        #expect(first.requests.contains(.read([0, 0, 0], known: false)))
        #expect(first.recall == .unknown)
        #expect(second.tree == Self.firstLaunchTree())
    }

    /// **A walk the read limit cut short is not remembered as walked for nothing** (SimWalk#86): what lies past the limit was never read, so the next read of the same shape walks again rather than finishing on a cached `.noRoot`.
    @Test
    func aWalkCutShortByTheReadLimitIsWalkedAgainOnTheNextRead() {
        let tree = Self.brokenTree()

        let cutShort = Self.replay(tree, in: Self.live(), readLimit: 6)
        let next = Self.replay(tree, in: Self.live(), recall: cutShort.recall)

        #expect(cutShort.root == nil)
        #expect(cutShort.recall == .unknown)
        #expect(next.tree == Self.firstLaunchTree())
    }

    /// **A walk whose limit runs out on a read is not remembered either** (SimWalk#86): the read of the app's own screen ahead of the host spends the last query, so the walk stops before its next visit with the sheet still past it.
    @Test
    func aWalkWhoseLimitRunsOutOnAReadIsWalkedAgainOnTheNextRead() {
        let tree = Self.brokenTree()
        let live = Self.live(before: [Live(mirroring: Self.progress)])

        let cutShort = Self.replay(tree, in: live, readLimit: 5)
        let next = Self.replay(tree, in: live, recall: cutShort.recall)

        #expect(cutShort.requests.last == .read([0, 0], known: false))
        #expect(cutShort.queries == 5)
        #expect(cutShort.recall == .unknown)
        #expect(next.tree == Self.firstLaunchTree())
    }

    /// **A walk that ran to its end on its last affordable query is remembered as one that found nothing** (SimWalk#56, #86): the limit only cuts short a walk with something left to visit.
    @Test
    func aWalkEndingExactlyAtItsReadLimitIsRemembered() {
        let tree = Self.brokenTree()
        let noSheet = Live(own: AXNode(type: "Application", frame: Self.screen), live: [
            Live(own: AXNode(type: "Window", frame: Self.screen), live: [Live(mirroring: Self.progress), Live(mirroring: tree.children[0].children[0])]),
        ])

        let unbounded = Self.replay(tree, in: noSheet)
        let exact = Self.replay(tree, in: noSheet, readLimit: unbounded.queries)

        #expect(unbounded.recall == .noRoot(RemoteContentGraft.Shape(of: tree)))
        #expect(exact.requests == unbounded.requests)
        #expect(exact.recall == unbounded.recall)
    }

    /// **A walk that could not read the content under a placeholder is not remembered as walked for nothing** (SimWalk#86): its snapshot failed mid-transition, no other candidate was seen, and the next read finds the sheet there with the tree's shape and the app's live count unchanged.
    @Test
    func aSheetUnreadableOnOneReadIsGraftedOnTheNext() {
        let tree = Self.brokenTree()
        let hierarchy = { (content: Live) in
            let placeholder = Live(own: AXNode(type: "Other", frame: Self.sheetBox), live: [content])
            let window = Live(own: AXNode(type: "Window", frame: Self.screen), live: [placeholder, Live(mirroring: Self.progress), Live(mirroring: tree.children[0].children[0])])
            return Live(own: AXNode(type: "Application", frame: Self.screen), live: [window])
        }
        let unreadable = hierarchy(Live(own: Self.sheet, live: Self.sheet.children.map(Live.init(mirroring:)), gone: true))
        let readable = hierarchy(Live(mirroring: Self.sheet))

        let first = Self.replay(tree, in: unreadable)
        let second = Self.replay(tree, in: readable, recall: first.recall)

        #expect(unreadable.descendants == readable.descendants)
        #expect(first.requests.contains(.read([0, 0, 0], known: false)))
        #expect(first.recall == .unknown)
        #expect(second.tree == Self.firstLaunchTree())
    }

    /// A sheet whose only labelled node outside its table is a large title at `titleY`, over rows of `labels` from `top`, with a childless anonymous `Other` at its own box.
    private static func titledTable(titleY: Double, top: Double, _ labels: [String]) -> AXNode {
        AXNode(type: "Other", frame: sheetBox, children: [
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 20, y: titleY, width: 362, height: 40), label: "Health Access"),
            AXNode(type: "Table", frame: AXNode.Frame(x: 0, y: 120, width: 402, height: 692), children: labels.enumerated().map { index, label in
                AXNode(type: "Cell", frame: AXNode.Frame(x: 22, y: top + 52 * Double(index), width: 358, height: 44), label: label)
            }),
            AXNode(type: "Other", frame: sheetBox),
        ])
    }

    private static func replay(_ tree: AXNode, in live: Live, recall: RemoteContentGraft.Recall = .unknown, readLimit: Int = 40) -> Replay {
        var graft = RemoteContentGraft(tree: tree, recall: recall, readLimit: readLimit)
        var requests: [RemoteContentGraft.Step] = []
        var step = graft.start()
        while true {
            switch step {
            case let .done(result, found):
                return Replay(tree: result, recall: found, requests: requests)
            case .countDescendants:
                requests.append(step)
                step = graft.next(.count(live.descendants))
            case let .countChildren(path):
                requests.append(step)
                step = graft.next(.count(live.element(at: path)?.live.count ?? 0))
            case let .read(path, _):
                requests.append(step)
                guard let element = live.element(at: path), !element.gone else {
                    step = graft.next(.unreadable)
                    continue
                }
                step = graft.next(.element(element.own))
            }
        }
    }
}

extension RemoteContentGraftTests {
    /// What a replayed walk came to, and every live read it asked for on the way.
    struct Replay {
        let tree: AXNode
        let recall: RemoteContentGraft.Recall
        let requests: [RemoteContentGraft.Step]

        /// The live queries the runner makes answering `requests`: `exists` ahead of a count below the app and of a known root's snapshot.
        var queries: Int {
            requests.reduce(0) { total, step in
                switch step {
                case let .countChildren(path): total + (path.isEmpty ? 1 : 2)
                case let .read(_, known): total + (known ? 2 : 1)
                case .countDescendants: total + 1
                case .done: total
                }
            }
        }

        /// The live path the remote root was found at, if it was.
        var root: [Int]? {
            guard case let .root(path) = recall else { return nil }
            return path
        }
    }

    /// One live element: its own snapshot, and its children as the live query counts them.
    struct Live {
        var own: AXNode
        var live: [Live]
        var gone = false

        /// An element whose live children are its snapshot's own.
        init(mirroring node: AXNode) {
            own = node
            live = node.children.map(Live.init(mirroring:))
        }

        init(own: AXNode, live: [Live], gone: Bool = false) {
            self.own = own
            self.live = live
            self.gone = gone
        }

        var descendants: Int {
            live.reduce(live.count) { $0 + $1.descendants }
        }

        func element(at path: [Int]) -> Live? {
            guard let index = path.first else { return self }
            return live.indices.contains(index) ? live[index].element(at: Array(path.dropFirst())) : nil
        }
    }
}
