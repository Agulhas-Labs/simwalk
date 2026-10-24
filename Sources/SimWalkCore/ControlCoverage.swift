//
// Copyright © Agulhas Labs
//

import Foundation

/// The controls a bundle's captured trees expose that no route in its manifest follows (SimWalk#35).
///
/// A walkbook reaches the states its author thought of. The tab, the filter button or the segment nobody routed through is on screen in the captures already, so the bundle can say what a unit would have to add a step for — read from the trees the walk wrote, with no simulator time spent.
///
/// **Covered means a route step's label would match the control**, by the same tiers the runner resolves a step's label by (`RouteTarget.matches(_:_:)`): its whole label, its identifier, a leading component, the same with its no-break spaces read as spaces, a `{n}` pattern, a lead-in to its data. Every screen's route counts, the steps an unreachable screen *tried* included — the walkbook does reach for that control, and that it failed to land is `bundle inspect`'s news, not a missing step. A control drawn selected counts as covered too: the state it would select is the one its capture already shows.
///
/// **Reported once, on the first screen it appears on.** A tab bar is on every screen, and a report naming `tab 'Workouts'` under each of them would be one finding stated eleven times. Controls are keyed by the step that would reach them, so a row seen in three states of a screen is one control.
///
/// Skips a screen recorded as `unexpectedScreen` for `DisclosureAffordanceAudit`'s reason: its captures are of whatever the walk reached instead, and a control found there would be filed under a screen it is not on. The findings name those screens, and the ones holding no captures, so a verdict over part of a walk says so.
public struct ControlCoverage {
    private let bundle: CaptureBundle

    public init(_ bundle: CaptureBundle) {
        self.bundle = bundle
    }

    /// Every reachable control the bundle's trees hold, and the ones no route step covers, in screen then state then tree order.
    public func findings() throws -> Findings {
        let routeLabels = bundle.manifest.screens.flatMap(Self.routeLabels(of:))
        var found: [Control] = []
        var notRead: [String] = []
        var wrongScreen: [String] = []
        var read: [String] = []
        for screen in bundle.manifest.screens {
            if case .unexpectedScreen = screen.outcome {
                wrongScreen.append(screen.id)
                continue
            }
            guard !screen.captures.isEmpty else {
                notRead.append(screen.id)
                continue
            }
            read.append(screen.id)
            for capture in screen.captures {
                found += try Self.controls(in: bundle.axTree(for: capture), screenID: screen.id, routeLabels: routeLabels)
            }
        }
        let covered = Set(found.filter(\.isCovered).map(\.key))
        var reported: Set<String> = []
        var printed: Set<String> = []
        var uncovered: [Uncovered] = []
        for control in found where !covered.contains(control.key) && !reported.contains(control.key) {
            reported.insert(control.key)
            // Two controls of one screen can shorten to the same step; it is one line to add, so it is stated once.
            if printed.insert("\(control.screenID)\u{0}\(control.step)").inserted {
                uncovered.append(Uncovered(screenID: control.screenID, step: control.step))
            }
        }
        return Findings(
            controls: reported.count + covered.count,
            uncovered: uncovered,
            screensRead: read,
            screensNotRead: notRead,
            screensWrongScreen: wrongScreen
        )
    }

    /// The element types a person taps to reach another state — the only ones counted as reachable.
    ///
    /// - `Button`: a plain button, and what XCUITest types a tab bar's items and a segmented control's options as — the tabs and filter segments this check exists to find.
    /// - `Tab`: the type a tab carries where the system draws its tabs outside a `TabBar` (a sidebar, a tab group).
    /// - `Cell`: a row that navigates when tapped.
    /// - `Link`: text that opens somewhere else.
    /// - `Switch` and `Toggle`: a setting whose other side is a state of its own; `Toggle` is the name the SDK gives a switch drawn as a button.
    ///
    /// Not a `TextField` or a search field: reaching one's other states is a `type` step with text an author has to choose, which no tree can suggest.
    static let reachableTypes: Set<String> = ["Button", "Tab", "Cell", "Link", "Switch", "Toggle"]

    /// The labels a screen's route targets: the steps it completed and, for an unreachable screen, the ones it tried.
    private static func routeLabels(of screen: CaptureManifest.ScreenRecord) -> [String] {
        var steps = screen.routeTaken
        if case let .unreachable(routeTried, _, _, _) = screen.outcome {
            steps += routeTried
        }
        return steps.compactMap(label(of:))
    }

    /// The label a step resolves by, or `nil` for a step that names no element.
    private static func label(of step: Walkbook.RouteStep) -> String? {
        switch step {
        case let .tab(label), let .tap(label), let .type(label, _, _), let .scrollTo(label), let .systemTap(label, _, _), let .longPress(label, _):
            label
        case let .tapPoint(label, _), let .swipe(label, _), let .drag(label, _, _, _, _):
            label
        case .openURL, .back:
            nil
        }
    }

    /// The reachable controls in one tree, each as the step that would reach it: `tab` for a tab, `tap` for anything else.
    ///
    /// **The step names a control by its leading component** — `tap 'Heart Rate Variability'` for a row labelled `Heart Rate Variability, 73, ms, ↑ +21 ms · 7d, good` — because that is a step the runner resolves (`RouteTarget.Match.leadingComponent`) and one that survives the data changing, where the whole label pins today's figures into the walkbook. The control is still *keyed* by its whole label, so two rows that share a leading component on different screens stay two findings.
    static func controls(in tree: AXNode, screenID: String, routeLabels: [String]) -> [Control] {
        var found: [Control] = []
        func visit(_ node: AXNode, insideTabBar: Bool) {
            if reachableTypes.contains(node.type), node.isEnabled, let name = name(of: node) {
                let isTab = insideTabBar || node.type == "Tab"
                let lead = shortestStep(for: name.components(separatedBy: ", ")[0], matching: node)
                found.append(Control(
                    screenID: screenID,
                    key: "\(isTab ? "tab" : "tap")\u{0}\(name)",
                    step: isTab ? .tab(label: lead) : .tap(label: lead),
                    isCovered: node.isSelected || routeLabels.contains { RouteTarget.matches($0, node) }
                ))
            }
            for child in node.children {
                visit(child, insideTabBar: insideTabBar || node.type == "TabBar")
            }
        }
        visit(tree, insideTabBar: false)
        return found
    }

    /// What a step would name the control by: its label, or its identifier where it has no label.
    private static func name(of node: AXNode) -> String? {
        [node.label, node.identifier].compactMap(\.self).first { !$0.isEmpty }
    }

    /// `lead` with a trailing numeric token dropped — `All 4` to `All` — when the remainder still resolves `node` through `RouteTarget.matches(_:_:)`'s own lead-in tier, so a count that only pins today's data does not ride into the suggested step.
    ///
    /// A lead that is only a number, or whose trimmed remainder no longer matches, is returned unchanged.
    private static func shortestStep(for lead: String, matching node: AXNode) -> String {
        guard let lastSeparator = lead.lastIndex(where: \.isWhitespace) else { return lead }
        let count = lead[lead.index(after: lastSeparator)...]
        guard !count.isEmpty, count.allSatisfy(\.isNumber) else { return lead }
        let trimmed = lead[..<lastSeparator].trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, RouteTarget.matches(trimmed, node) else { return lead }
        return trimmed
    }
}

public extension ControlCoverage {
    /// One control no route step covers, and the screen it was first seen on.
    struct Uncovered: Equatable, Sendable {
        public let screenID: String
        /// The step that would reach it — `tab 'Workouts'`, `tap 'Filter'` — as a walkbook writes it.
        public let step: Walkbook.RouteStep

        public init(screenID: String, step: Walkbook.RouteStep) {
            self.screenID = screenID
            self.step = step
        }
    }

    /// What the check found, and what it could read to find it.
    struct Findings: Equatable, Sendable {
        /// Distinct reachable controls across every screen read.
        public let controls: Int
        /// Those no route step covers, each once, on the first screen it appears on.
        public let uncovered: [Uncovered]
        /// Screens whose captures were read.
        public let screensRead: [String]
        /// Screens holding no captures at all, whose controls nothing could see.
        public let screensNotRead: [String]
        /// Screens recorded as `unexpectedScreen`, whose captures are of another screen and were not read.
        public let screensWrongScreen: [String]

        public init(controls: Int, uncovered: [Uncovered], screensRead: [String], screensNotRead: [String] = [], screensWrongScreen: [String] = []) {
            self.controls = controls
            self.uncovered = uncovered
            self.screensRead = screensRead
            self.screensNotRead = screensNotRead
            self.screensWrongScreen = screensWrongScreen
        }
    }

    /// One control as one capture showed it.
    struct Control: Equatable, Sendable {
        public let screenID: String
        /// What makes two captures of it one control: the kind of step and its whole label (or identifier).
        public let key: String
        public let step: Walkbook.RouteStep
        /// Whether a route step's label matches it, or it is drawn selected.
        public let isCovered: Bool
    }
}
