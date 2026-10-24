//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore

/// A scripted app a `discover` crawl drives with no simulator: screens as trees, the labels that push each one, the tabs, and a stack the back button pops.
///
/// Every step sent is recorded, so a test can say what was tapped; a tap on a label with nowhere to go is answered `blocked`, as a button that acts without navigating would be by a step expecting a new screen. **A tap resolves its label as the runner does** (`RouteTarget.choose`, so a leading component reaches `Erase, all data`), and the element it landed on is recorded beside it. From the first relaunch on, `afterRelaunch`'s screens replace those of the same name: an app that starts in another state.
final class FakeDiscoveryApp: DiscoverySession {
    let launch: String
    let tabs: [String: String]
    private(set) var screens: [String: Screen]
    let afterRelaunch: [String: Screen]
    private(set) var stack: [String]
    private(set) var sent: [Walkbook.RouteStep] = []
    /// The label of each element a `tap` landed on, in order.
    private(set) var hits: [String] = []
    private(set) var relaunches = 0
    /// The direction of each `scroll` the crawl dragged, in order, whether or not it moved anything.
    private(set) var scrolls: [LiveSessionScroll.Direction] = []
    /// How far each lazy screen's list is scrolled, by screen name; kept across `back`, reset by `relaunch`.
    private var offsets: [String: Double] = [:]

    /// Labels a `scrollTo` is answered `blocked` for, as a list that will not scroll its row on screen.
    let unscrollable: Set<String>
    /// The screens whose `scroll` is answered `nil`, as a runner that cannot drag their list.
    let scrollFails: Set<String>
    /// The screens whose `.up` drag is answered `nil`, as a runner that can drag a list down but not back.
    let upFails: Set<String>
    /// The screens a drag changes in place, by screen name: each drag takes the next of these as the screen, with the list scrolled nowhere, as a row that grows or a "load more" row appended; a drag past the last leaves it.
    private var changesOnDrag: [String: [Screen]]

    init(launch: String, tabs: [String: String] = [:], screens: [String: Screen], afterRelaunch: [String: Screen] = [:], unscrollable: Set<String> = [], scrollFails: Set<String> = [], upFails: Set<String> = [], changesOnDrag: [String: [Screen]] = [:]) {
        self.launch = launch
        self.unscrollable = unscrollable
        self.scrollFails = scrollFails
        self.upFails = upFails
        self.changesOnDrag = changesOnDrag
        self.tabs = tabs
        self.screens = screens
        self.afterRelaunch = afterRelaunch
        stack = [launch]
    }

    /// The labels of every `tap` sent, in order.
    var tapped: [String] {
        sent.compactMap { step in
            if case let .tap(label) = step {
                return label
            }
            return nil
        }
    }

    func read() -> LiveScreen {
        live(of: stack.last ?? launch)
    }

    func send(_ step: Walkbook.RouteStep) -> LiveSessionResponse {
        sent.append(step)
        let here = stack.last ?? launch
        let tree = tree(of: here)
        let landed: Bool = switch step {
        case let .tab(label):
            tabs[label].map { stack = [$0] } != nil
        case let .tap(label):
            tap(label, in: tree, on: here)
        case let .scrollTo(label):
            scrollTo(label, in: tree, on: here)
        case .back:
            screens[here]?.hasBack == true && stack.count > 1 && stack.popLast() != nil
        default:
            false
        }
        let after = self.tree(of: stack.last ?? launch)
        let delta = ScreenDelta(from: tree, to: after)
        return LiveSessionResponse(n: sent.count, action: .step, screen: live(of: stack.last ?? launch), step: landed ? .landed(step, delta: delta) : .blocked(reason: "nothing to land on", delta: delta))
    }

    func relaunch() -> LiveScreen {
        relaunches += 1
        screens.merge(afterRelaunch) { _, later in later }
        offsets = [:]
        stack = [launch]
        return read()
    }

    /// One drag of the list: a lazy screen's offset moves by 0.6 of the container's height, down or up, and stops at either end of the content; a screen that is not lazy shows the same rows.
    func scroll(_ scroll: LiveSessionScroll) -> LiveScreen? {
        scrolls.append(scroll.direction)
        let here = stack.last ?? launch
        guard !scrollFails.contains(here), scroll.direction != .up || !upFails.contains(here) else { return nil }
        if let next = changesOnDrag[here]?.first {
            screens[here] = next
            changesOnDrag[here]?.removeFirst()
        } else if let screen = screens[here], screen.isLazy {
            let step = 0.6 * screen.containerHeight * (scroll.direction == .down ? 1 : -1)
            offsets[here] = screen.clamped((offsets[here] ?? 0) + step)
        }
        return read()
    }

    /// Lands when a row of the whole content has the label as a prefix, and brings that row into a lazy list's viewport.
    private func scrollTo(_ label: String, in tree: AXNode, on here: String) -> Bool {
        guard !unscrollable.contains(label) else { return false }
        guard let screen = screens[here], screen.isLazy else {
            return tree.flattened.contains { $0.label?.hasPrefix(label) == true }
        }
        guard let row = screen.content.first(where: { $0.label?.hasPrefix(label) == true }) else { return false }
        let offset = offsets[here] ?? 0
        if row.frame.y < Screen.listTop + offset || row.frame.maxY > Screen.listTop + screen.containerHeight + offset {
            offsets[here] = screen.clamped(row.frame.y - Screen.listTop)
        }
        return true
    }

    /// Taps what the runner's lookup chooses for `label`, and pushes where that element leads, if anywhere.
    private func tap(_ label: String, in tree: AXNode, on here: String) -> Bool {
        guard case let .chosen(target, _) = RouteTarget.choose(labelled: label, in: tree, reaching: .control), let name = target.node.label else { return false }
        hits.append(name)
        return screens[here]?.taps[name].map { stack.append($0) } != nil
    }

    private func live(of screen: String) -> LiveScreen {
        Self.live(tree(of: screen), systemAlert: screens[screen]?.systemAlert)
    }

    private func tree(of screen: String) -> AXNode {
        screens[screen]?.tree(offset: offsets[screen] ?? 0) ?? AXNode(type: "Application", frame: Self.bounds)
    }

    static let bounds = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)

    static func live(_ tree: AXNode, systemAlert: LiveScreen.SystemAlert? = nil) -> LiveScreen {
        LiveScreen(
            appBundleID: "dev.simwalk.discover",
            device: CaptureManifest.Device(name: "iPhone 17", udid: "UDID-1", osVersion: "27.0"),
            runnerCommit: nil,
            readAt: Date(timeIntervalSince1970: 0),
            nonce: "d1",
            appState: .foreground,
            tree: tree,
            settled: true,
            screenPixels: nil,
            systemAlert: systemAlert
        )
    }
}

extension FakeDiscoveryApp {
    /// One screen: its tree, whether its navigation bar has a back button, and where each tappable label leads.
    struct Screen {
        /// The screen at the top of its list; a lazy screen's tree at another offset is ``tree(offset:)``.
        let tree: AXNode
        let hasBack: Bool
        let taps: [String: String]
        /// The system alert SpringBoard draws over the screen, which its own tree does not show.
        let systemAlert: LiveScreen.SystemAlert?
        /// Whether the list builds only the rows near the visible part, as a lazy list does.
        let isLazy: Bool
        /// Every content node of the list, laid out in full whatever is loaded.
        let content: [AXNode]
        /// The height of the list's fixed frame, from ``listTop`` to the visible bottom.
        let containerHeight: Double
        private let contentHeight: Double
        private let make: (Double) -> AXNode

        static let listTop = 116.0

        /// A screen laid out as a list: a navigation bar (with a back button when `back`), its texts, disclosure rows, other controls, an alert over it, and a tab bar.
        ///
        /// A row whose label is in `plain` is a cell with no disclosure glyph: a list's filler, never tapped.
        ///
        /// **When `lastRowGrowth`**, the last row is that many points taller, as a row that wrapped: the content below it is not moved.
        ///
        /// **When `gapAfterFirstRow`**, the rows after the first sit that many points lower, as content scrolled under a pinned first row.
        ///
        /// **When `scrolledIdentifier`**, the container carries it instead of `identifier` once the list is scrolled, as a pushed screen's list does. The content sits in a plain `Other`, or in a `Table` that ends at the screen's bottom when `table`, as a scrolling list does. **When `lazy`**, the container's frame is fixed from y 116 to the visible bottom (the tab bar's top, else the screen's), and the tree holds only the content intersecting that window at the screen's scroll offset, drawn where it sits in the window.
        init(
            title: String? = nil,
            identifier: String? = nil,
            back: Bool = false,
            texts: [String] = [],
            rows: [String] = [],
            controls: [(type: String, label: String)] = [],
            alert: [String]? = nil,
            systemAlert: [String]? = nil,
            tabs: [String] = [],
            table: Bool = false,
            taps: [String: String] = [:],
            plain: Set<String> = [],
            lazy: Bool = false,
            firstRowIdentifier: String? = nil,
            outsideIdentifiers: (resting: String, scrolled: String)? = nil,
            scrolledIdentifier: String? = nil,
            lastRowGrowth: Double = 0,
            gapAfterFirstRow: Double = 0
        ) {
            var content: [AXNode] = []
            var y = 120.0
            if let firstRowIdentifier {
                content.append(AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: y, width: 402, height: 20), identifier: firstRowIdentifier))
                y += 20
            }
            for text in texts {
                content.append(AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: y, width: 200, height: 20), label: text))
                y += 30
            }
            for (index, row) in rows.enumerated() {
                let growth = index == rows.count - 1 ? lastRowGrowth : 0
                let glyph = AXNode(type: "Image", frame: AXNode.Frame(x: 378, y: y + 15, width: 8, height: 14))
                content.append(AXNode(type: "Cell", frame: AXNode.Frame(x: 0, y: y, width: 402, height: 44 + growth), label: row, children: plain.contains(row) ? [] : [glyph]))
                y += 44
                if index == 0 {
                    y += gapAfterFirstRow
                }
            }
            for control in controls {
                content.append(AXNode(type: control.type, frame: AXNode.Frame(x: 16, y: y, width: 370, height: 44), label: control.label))
                y += 44
            }
            var window: [AXNode] = []
            if title != nil || back {
                var bar: [AXNode] = []
                if back {
                    bar.append(AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 62, width: 44, height: 44), label: "Back", identifier: DiscoverBackButton.identifier))
                }
                if let title {
                    bar.append(AXNode(type: "StaticText", frame: AXNode.Frame(x: 150, y: 70, width: 100, height: 30), label: title))
                }
                window.append(AXNode(type: "NavigationBar", frame: AXNode.Frame(x: 0, y: 62, width: 402, height: 54), identifier: title, children: bar))
            }
            let bottom = lazy ? (tabs.isEmpty ? FakeDiscoveryApp.bounds.height : 791) : table ? min(y, FakeDiscoveryApp.bounds.height) : y
            let all = content
            let frame = AXNode.Frame(x: 0, y: Self.listTop, width: 402, height: max(bottom - Self.listTop, 1))
            let container = { (offset: Double) -> AXNode in
                let loaded = lazy ? all.filter { $0.frame.y < bottom + offset && $0.frame.maxY > Self.listTop + offset }.map { Self.moved($0, by: -offset) } : all
                return AXNode(type: table ? "Table" : "Other", frame: frame, identifier: offset > 0 ? scrolledIdentifier ?? identifier : identifier, children: loaded)
            }
            let head = window
            var tail: [AXNode] = []
            if !tabs.isEmpty {
                let width = 402.0 / Double(tabs.count)
                let buttons = tabs.enumerated().map { index, tab in
                    AXNode(type: "Button", frame: AXNode.Frame(x: Double(index) * width, y: 795, width: width, height: 54), label: tab)
                }
                tail.append(AXNode(type: "TabBar", frame: AXNode.Frame(x: 0, y: 791, width: 402, height: 83), label: "Tab Bar", children: buttons))
            }
            if let alert {
                let buttons = alert.enumerated().map { index, label in
                    AXNode(type: "Button", frame: AXNode.Frame(x: 60 + Double(index) * 140, y: 480, width: 140, height: 44), label: label)
                }
                tail.append(AXNode(type: "Alert", frame: AXNode.Frame(x: 60, y: 380, width: 282, height: 150), label: "Are you sure?", children: buttons))
            }
            let outside = { (offset: Double) -> [AXNode] in
                guard let outsideIdentifiers else { return [] }
                return [AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 100, width: 402, height: 10), identifier: offset > 0 ? outsideIdentifiers.scrolled : outsideIdentifiers.resting)]
            }
            let build = { (offset: Double) -> AXNode in
                AXNode(type: "Application", frame: FakeDiscoveryApp.bounds, label: "Fake", children: [
                    AXNode(type: "Window", frame: FakeDiscoveryApp.bounds, children: head + outside(offset) + [container(offset)] + tail),
                ])
            }
            make = build
            tree = build(0)
            isLazy = lazy
            self.content = content
            containerHeight = frame.height
            contentHeight = y - Self.listTop
            hasBack = back
            self.taps = taps
            self.systemAlert = systemAlert.map { labels in
                LiveScreen.SystemAlert(title: "Allow notifications?", buttons: labels.enumerated().map { index, label in
                    LiveScreen.SystemAlert.Button(label: label, frame: AXNode.Frame(x: 60 + Double(index) * 140, y: 480, width: 140, height: 44))
                })
            }
        }

        /// The screen's tree with the list scrolled `offset` points.
        func tree(offset: Double) -> AXNode {
            make(offset)
        }

        /// `offset` held to the ends of the content.
        func clamped(_ offset: Double) -> Double {
            min(max(offset, 0), max(contentHeight - containerHeight, 0))
        }

        private static func moved(_ node: AXNode, by dy: Double) -> AXNode {
            var node = node
            node.frame.y += dy
            node.children = node.children.map { moved($0, by: dy) }
            return node
        }
    }
}
