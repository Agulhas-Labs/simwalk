//
// Copyright © Agulhas Labs
//

import Foundation

/// The bounded crawl behind `discover`: taps an app's navigation affordances from launch and drafts a walkbook screen for each distinct form it reaches.
///
/// **Depth first, in visual order.** Each tab's screen is a root at depth 0, reached by `tab`; each disclosure row tapped adds one. A screen at the depth bound is drafted and its rows are listed as beyond depth; once the draft holds `maxScreens`, every row still to tap is listed as beyond max screens. **Getting back** is the back button where the screen has one (``DiscoverBackButton``), checked by form on arrival; otherwise, or when that check fails, a relaunch and the route replayed — **each tap of the replay held to the screen it was first taken from**: the screen's form is the one the crawl tapped the row on, and the runner's lookup still names that row by its label and nothing else, since a `tap` also takes a leading-component match and searches for a label it cannot see, and an app relaunched into another state could answer it with a control the crawl never classified. A crawl that cannot get back to a screen lists its remaining rows as such rather than tapping them somewhere else.
public struct DiscoverCrawl {
    public static let defaultDepth = 2
    public static let defaultMaxScreens = 25

    /// The app the draft names.
    public let appBundleID: String
    /// The one capture state every drafted screen carries — the session's.
    public let state: Walkbook.CaptureState
    /// How many disclosure-row taps from a root the crawl goes.
    public let depth: Int
    /// The most screens the draft holds.
    public let maxScreens: Int
    private let segmenter: any Segmenter

    public init(appBundleID: String, state: Walkbook.CaptureState, depth: Int = defaultDepth, maxScreens: Int = defaultMaxScreens, segmenter: any Segmenter = AXSegmenter()) {
        self.appBundleID = appBundleID
        self.state = state
        self.depth = depth
        self.maxScreens = maxScreens
        self.segmenter = segmenter
    }

    /// Crawls the app `session` is driving, from the screen it is on now — its launch screen.
    public func run(on session: some DiscoverySession) throws -> DiscoverResult {
        let crawl = Run(crawl: self, session: session)
        try crawl.start()
        return crawl.result()
    }
}

extension DiscoverCrawl {
    /// One crawl's progress: the draft so far and the screen the app is on.
    private final class Run<Session: DiscoverySession> {
        let crawl: DiscoverCrawl
        let session: Session
        var screens: [Walkbook.Screen] = []
        var drafted: [DiscoverForm: String] = [:]
        /// The slugs of the screen ids taken, `launch` among them from the start: the skipped list files the tabs under it.
        var slugs: Set<String> = [CaptureBundleLayout.slugSegment("launch")]
        var skipped: [DiscoverSkip] = []
        var duplicates: [DiscoverResult.Duplicate] = []
        /// The drafted screens whose list may continue below the rows the app loaded, in draft order.
        var belowTheFold: [String] = []
        /// The tree last read, or `nil` when the app was not running.
        var current: AXNode?
        /// The system alert over the app in the screen last read, if any.
        var systemAlert: LiveScreen.SystemAlert?

        init(crawl: DiscoverCrawl, session: Session) {
            self.crawl = crawl
            self.session = session
        }

        func start() throws {
            let first = try session.read()
            guard let launch = first.tree else { throw DiscoverError.appNotRunning }
            current = launch
            systemAlert = first.systemAlert
            let tabs = DiscoverClassifier.tabs(in: launch)
            skipped += tabs.skipped
            guard !tabs.labels.isEmpty else {
                guard let anchor = DiscoverClassifier.anchor(in: launch) else { throw DiscoverError.nothingToRouteBy }
                try visit(launch, legs: [Leg(steps: [.scrollTo(label: anchor)])], depth: 0, slug: "root", parent: nil)
                return
            }
            let tabNodes = DiscoverClassifier.visualOrder(launch.flattened.filter { tabs.labels.contains($0.label ?? "") && $0.type != "TabBar" }, frame: \.frame)
            for label in tabs.labels {
                let node = tabNodes.first { $0.label == label }
                let frame = node?.frame ?? launch.frame
                let entry = { (reason: DiscoverSkip.Reason) in
                    DiscoverSkip(screenID: "launch", type: node?.type ?? "Button", name: label, reason: reason, frame: frame)
                }
                guard screens.count < crawl.maxScreens else {
                    skipped.append(entry(.beyondMaxScreens))
                    continue
                }
                let route: [Walkbook.RouteStep] = [.tab(label: label)]
                guard let root = try follow(route) else {
                    skipped.append(entry(.didNotLand))
                    try relaunch()
                    continue
                }
                if endsBranch(root) {
                    skipped.append(entry(.alertEndsBranch))
                    skipped += alertButtons(of: root, screenID: "launch")
                    try relaunch()
                    continue
                }
                try visit(root, legs: [Leg(steps: route)], depth: 0, slug: Self.slug(label), parent: nil)
            }
        }

        func result() -> DiscoverResult {
            let order = ["launch"] + screens.map(\.id)
            let ordered = order.flatMap { id in
                DiscoverClassifier.visualOrder(skipped.filter { $0.screenID == id }, frame: \.frame)
            }
            return DiscoverResult(
                walkbook: Walkbook(name: crawl.appBundleID, appBundleID: crawl.appBundleID, screens: screens),
                skipped: ordered,
                duplicates: duplicates,
                depth: crawl.depth,
                maxScreens: crawl.maxScreens,
                belowTheFold: belowTheFold
            )
        }

        /// Drafts the screen `tree` is of, unless its form is drafted already, then taps each of its rows and comes back.
        private func visit(_ tree: AXNode, legs: [Leg], depth: Int, slug: String, parent: String?) throws {
            let route = legs.flatMap(\.steps)
            let form = DiscoverForm(of: tree, segmenter: crawl.segmenter)
            if let existing = drafted[form] {
                duplicates.append(DiscoverResult.Duplicate(route: route, screenID: existing))
                return
            }
            let id = claim(slug, parent: parent)
            drafted[form] = id
            screens.append(Walkbook.Screen(id: id, route: route, states: [crawl.state], expect: tree.screenIdentifier))
            if DiscoverClassifier.listMayContinue(tree) {
                belowTheFold.append(id)
            }
            let read = DiscoverClassifier.read(tree, screenID: id)
            skipped += read.skipped
            for (index, row) in read.rows.enumerated() {
                let entry = { (reason: DiscoverSkip.Reason) in
                    DiscoverSkip(screenID: id, type: row.node.type, name: row.label, reason: reason, frame: row.node.frame)
                }
                if depth >= crawl.depth {
                    skipped.append(entry(.beyondDepth))
                    continue
                }
                guard screens.count < crawl.maxScreens else {
                    skipped.append(entry(.beyondMaxScreens))
                    continue
                }
                let steps: [Walkbook.RouteStep] = row.isOnScreen ? [.tap(label: row.label)] : [.scrollTo(label: row.label), .tap(label: row.label)]
                let leg = Leg(steps: steps, from: form, row: row)
                if !row.isOnScreen, try follow([.scrollTo(label: row.label)]) == nil {
                    skipped.append(entry(.couldNotScroll))
                } else if let child = try follow([.tap(label: row.label)]) {
                    if endsBranch(child) {
                        skipped.append(entry(.alertEndsBranch))
                        skipped += alertButtons(of: child, screenID: id)
                    } else {
                        try visit(child, legs: legs + [leg], depth: depth + 1, slug: Self.slug(row.label), parent: id)
                    }
                } else {
                    skipped.append(entry(.didNotLand))
                }
                guard try back(to: form, by: legs) else {
                    skipped += read.rows.dropFirst(index + 1).map { remaining in
                        DiscoverSkip(screenID: id, type: remaining.node.type, name: remaining.label, reason: .couldNotReturn, frame: remaining.node.frame)
                    }
                    return
                }
            }
        }

        /// Sends `steps` in turn and returns the screen the last one left the app on, or `nil` when one did not land.
        private func follow(_ steps: [Walkbook.RouteStep]) throws -> AXNode? {
            for step in steps {
                let response = try session.send(step)
                guard let answer = response.step else {
                    throw DiscoverError.stepFailed(step: step, failure: response.failure ?? "no step answer")
                }
                let screen = try response.screen ?? session.read()
                current = screen.tree
                systemAlert = screen.systemAlert
                guard answer.outcome == .landed, current != nil else { return nil }
            }
            return current
        }

        /// Gets the app back to the screen of `form`: it may be there already, else by the back button, else by a relaunch and `legs` replayed — and says whether it is.
        private func back(to form: DiscoverForm, by legs: [Leg]) throws -> Bool {
            if isOn(form), systemAlert == nil {
                return true
            }
            if let tree = current, !endsBranch(tree), DiscoverBackButton.of(tree) != nil, try follow([.back]) != nil, isOn(form) {
                return true
            }
            try relaunch()
            return try replay(legs) && isOn(form)
        }

        /// Sends each leg's steps in turn, and says whether every one landed — stopping, with nothing sent, at a row leg whose screen is no longer the form it was tapped on or whose row the runner's lookup no longer names alone.
        private func replay(_ legs: [Leg]) throws -> Bool {
            for leg in legs {
                if let form = leg.from, !isOn(form) {
                    return false
                }
                for step in leg.steps {
                    if case let .tap(label) = step, let row = leg.row, !stillNames(row, by: label) {
                        return false
                    }
                    guard try follow([step]) != nil else { return false }
                }
            }
            return true
        }

        /// Whether a `tap` labelled `label` on the screen as it stands lands on `row` alone: the screen has a disclosure row the runner's lookup names by `label` and nothing else (``DiscoverClassifier/read(_:screenID:)``), of the type and identifier the crawl tapped.
        private func stillNames(_ row: DiscoverClassifier.Row, by label: String) -> Bool {
            guard let tree = current else { return false }
            return DiscoverClassifier.read(tree, screenID: "").rows.contains { found in
                found.label == label && found.node.type == row.node.type && found.node.identifier == row.node.identifier
            }
        }

        private func isOn(_ form: DiscoverForm) -> Bool {
            current.map { DiscoverForm(of: $0, segmenter: crawl.segmenter) } == form
        }

        private func relaunch() throws {
            let screen = try session.relaunch()
            current = screen.tree
            systemAlert = screen.systemAlert
        }

        /// Whether an alert covers the screen `tree` is of: one in the app's own tree, or the system's over it.
        private func endsBranch(_ tree: AXNode) -> Bool {
            DiscoverClassifier.hasAlert(tree) || systemAlert != nil
        }

        /// The buttons of the alerts over the screen, as skipped entries: the app's own, and the system's from the live screen.
        private func alertButtons(of tree: AXNode, screenID: String) -> [DiscoverSkip] {
            let system = (systemAlert?.buttons ?? []).map { button in
                DiscoverSkip(screenID: screenID, type: "Button", name: button.label, reason: .alertButton, frame: button.frame)
            }
            return DiscoverClassifier.read(tree, screenID: screenID).skipped.filter { $0.reason == .alertButton } + system
        }

        /// A screen id no drafted screen's directory collides with: the label's slug, then the parent's id before it, then a count after.
        private func claim(_ slug: String, parent: String?) -> String {
            var candidates = [slug]
            if let parent {
                candidates.append("\(parent)-\(slug)")
            }
            let base = candidates.last ?? slug
            var count = 2
            while true {
                if let free = candidates.first(where: { !slugs.contains(CaptureBundleLayout.slugSegment($0)) }) {
                    slugs.insert(CaptureBundleLayout.slugSegment(free))
                    return free
                }
                candidates = ["\(base)-\(count)"]
                count += 1
            }
        }

        /// `label` lowercased, every run of anything but letters and digits written `-`, and trimmed of them; `screen` where nothing is left.
        static func slug(_ label: String) -> String {
            var slug = ""
            for character in label.lowercased() {
                if character.isLetter || character.isNumber {
                    slug.append(character)
                } else if !slug.isEmpty, slug.last != "-" {
                    slug.append("-")
                }
            }
            while slug.last == "-" {
                slug.removeLast()
            }
            return slug.isEmpty ? "screen" : slug
        }
    }
}

private extension DiscoverCrawl {
    /// One hop of a route as the crawl took it: the steps sent and, for a row's hop, the form of the screen it was taken from and the row tapped, which a replay holds the app to before it taps.
    struct Leg {
        let steps: [Walkbook.RouteStep]
        var from: DiscoverForm?
        var row: DiscoverClassifier.Row?
    }
}
