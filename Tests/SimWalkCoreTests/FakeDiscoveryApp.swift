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

    /// Labels a `scrollTo` is answered `blocked` for, as a list that will not scroll its row on screen.
    let unscrollable: Set<String>

    init(launch: String, tabs: [String: String] = [:], screens: [String: Screen], afterRelaunch: [String: Screen] = [:], unscrollable: Set<String> = []) {
        self.launch = launch
        self.unscrollable = unscrollable
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
            !unscrollable.contains(label) && tree.flattened.contains { $0.label?.hasPrefix(label) == true }
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
        stack = [launch]
        return read()
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
        screens[screen]?.tree ?? AXNode(type: "Application", frame: Self.bounds)
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
        let tree: AXNode
        let hasBack: Bool
        let taps: [String: String]
        /// The system alert SpringBoard draws over the screen, which its own tree does not show.
        let systemAlert: LiveScreen.SystemAlert?

        /// A screen laid out as a list: a navigation bar (with a back button when `back`), its texts, disclosure rows, other controls, an alert over it, and a tab bar.
        ///
        /// The content sits in a plain `Other`, or in a `Table` that ends at the screen's bottom when `table`, as a scrolling list does.
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
            taps: [String: String] = [:]
        ) {
            var content: [AXNode] = []
            var y = 120.0
            for text in texts {
                content.append(AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: y, width: 200, height: 20), label: text))
                y += 30
            }
            for row in rows {
                let glyph = AXNode(type: "Image", frame: AXNode.Frame(x: 378, y: y + 15, width: 8, height: 14))
                content.append(AXNode(type: "Cell", frame: AXNode.Frame(x: 0, y: y, width: 402, height: 44), label: row, children: [glyph]))
                y += 44
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
            let bottom = table ? min(y, FakeDiscoveryApp.bounds.height) : y
            window.append(AXNode(type: table ? "Table" : "Other", frame: AXNode.Frame(x: 0, y: 116, width: 402, height: max(bottom - 116, 1)), identifier: identifier, children: content))
            if !tabs.isEmpty {
                let width = 402.0 / Double(tabs.count)
                let buttons = tabs.enumerated().map { index, tab in
                    AXNode(type: "Button", frame: AXNode.Frame(x: Double(index) * width, y: 795, width: width, height: 54), label: tab)
                }
                window.append(AXNode(type: "TabBar", frame: AXNode.Frame(x: 0, y: 791, width: 402, height: 83), label: "Tab Bar", children: buttons))
            }
            if let alert {
                let buttons = alert.enumerated().map { index, label in
                    AXNode(type: "Button", frame: AXNode.Frame(x: 60 + Double(index) * 140, y: 480, width: 140, height: 44), label: label)
                }
                window.append(AXNode(type: "Alert", frame: AXNode.Frame(x: 60, y: 380, width: 282, height: 150), label: "Are you sure?", children: buttons))
            }
            tree = AXNode(type: "Application", frame: FakeDiscoveryApp.bounds, label: "Fake", children: [
                AXNode(type: "Window", frame: FakeDiscoveryApp.bounds, children: window),
            ])
            hasBack = back
            self.taps = taps
            self.systemAlert = systemAlert.map { labels in
                LiveScreen.SystemAlert(title: "Allow notifications?", buttons: labels.enumerated().map { index, label in
                    LiveScreen.SystemAlert.Button(label: label, frame: AXNode.Frame(x: 60 + Double(index) * 140, y: 480, width: 140, height: 44))
                })
            }
        }
    }
}
