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
    /// The most pages of one list the crawl keeps, the first included.
    static let pageLimit = 10

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
        /// The drafted screens whose list may continue below the rows read, each with why paging stopped, in draft order.
        var belowTheFold: [DiscoverResult.OpenList] = []
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

        /// The rows of the screen `tree` is of: the screen's own, or, where a list reaches the bottom and its rows will be tapped, the whole list's, dragged page by page and then back to the top.
        ///
        /// A list is left open, with why, when it is not dragged or paging stops before its end; `returned` is false when the screen could not be got back to after the drags.
        ///
        /// Once a drag down was answered, the form check is trusted only when a drag up was then seen to move nothing: `DiscoverForm` compares text shapes, not frames, so a list left scrolled passes it. Otherwise the app is relaunched and replayed without asking `isOn` first.
        private func readRows(of tree: AXNode, id: String, form: DiscoverForm, legs: [Leg], depth: Int) throws -> ScreenRead {
            guard let list = DiscoverClassifier.continuingList(tree) else {
                let read = DiscoverClassifier.read(tree, screenID: id)
                return ScreenRead(rows: read.rows, skipped: read.skipped, returned: true)
            }
            guard depth < crawl.depth, screens.count < crawl.maxScreens else {
                belowTheFold.append(DiscoverResult.OpenList(screenID: id, why: depth >= crawl.depth ? "not scrolled: beyond depth" : "not scrolled: beyond max screens"))
                let read = DiscoverClassifier.read(tree, screenID: id)
                return ScreenRead(rows: read.rows, skipped: read.skipped, returned: true)
            }
            var pages = DiscoverListPages(first: tree, container: list, screenID: id)
            var kept = 1
            var rewind = false
            var dragged = false
            var why: String?
            paging: while true {
                guard kept < DiscoverCrawl.pageLimit else {
                    why = "stopped after \(DiscoverCrawl.pageLimit) pages"
                    rewind = true
                    break paging
                }
                guard let screen = try session.scroll(LiveSessionScroll(direction: .down, container: list.frame)) else {
                    why = "the runner could not scroll it"
                    break paging
                }
                dragged = true
                current = screen.tree
                systemAlert = screen.systemAlert
                guard let page = screen.tree, identifiers(of: page, outside: list) == identifiers(of: tree, outside: list), screen.systemAlert == nil else {
                    why = "the screen changed while scrolling"
                    break paging
                }
                switch pages.add(page) {
                case .moved:
                    kept += 1
                case .end:
                    rewind = true
                    break paging
                case .unjoined:
                    why = "two pages could not be joined"
                    rewind = true
                    break paging
                case .changedInPlace:
                    why = "the list changed without scrolling"
                    rewind = true
                    break paging
                case .containerGone:
                    why = "the list was gone after a scroll"
                    break paging
                }
            }
            var atTop = !dragged
            if rewind {
                atTop = try scrollToTop(of: list, drags: kept + 2)
            }
            if let why {
                belowTheFold.append(DiscoverResult.OpenList(screenID: id, why: why))
            }
            let read = pages.read()
            let returned = try atTop ? back(to: form, by: legs) : relaunchAndReplay(to: form, by: legs)
            return ScreenRead(rows: read.rows, skipped: read.skipped, returned: returned)
        }

        /// The screen-level identifiers of `page` that no descendant of the list's container carries, in order (the container's own identifier usually names the screen, so it stays): what names the screen once the rows that scroll away are set aside.
        ///
        /// The list is found on `page` as ``DiscoverListPages`` finds it; when it is not there nothing is set aside, and the `containerGone` stop catches that a step later.
        private func identifiers(of page: AXNode, outside list: AXNode) -> [String] {
            let all = ScreenIdentifierRule.screenLevelIdentifiers(in: page)
            guard let found = DiscoverListPages.list(in: page, like: list) else { return all }
            let inside = Set(found.children.flatMap(\.flattened).compactMap(\.identifier))
            return all.filter { !inside.contains($0) }
        }

        /// Drags `list` up until a drag moves nothing, at most `drags` times, and stops where the runner cannot drag; says whether a drag was answered and seen to move nothing (a shift under a point, or the list stayed put while it changed in place, SimWalk#208), which is the only proof the list is at its top.
        private func scrollToTop(of list: AXNode, drags: Int) throws -> Bool {
            for _ in 0 ..< drags {
                guard let before = current, let screen = try session.scroll(LiveSessionScroll(direction: .up, container: list.frame)) else { return false }
                current = screen.tree
                systemAlert = screen.systemAlert
                guard let after = screen.tree else { return false }
                if let shift = DiscoverListPages.shift(from: before, to: after, container: list), abs(shift) < 1 {
                    return true
                }
                if DiscoverListPages.stayedPut(from: before, to: after, container: list) {
                    return true
                }
            }
            return false
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
            let read = try readRows(of: tree, id: id, form: form, legs: legs, depth: depth)
            skipped += read.skipped
            guard read.returned else {
                skipped += read.rows.map { row in
                    DiscoverSkip(screenID: id, type: row.node.type, name: row.label, reason: .couldNotReturn, frame: row.node.frame)
                }
                return
            }
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
            return try relaunchAndReplay(to: form, by: legs)
        }

        /// Relaunches the app and replays `legs`, and says whether it is on the screen of `form`.
        private func relaunchAndReplay(to form: DiscoverForm, by legs: [Leg]) throws -> Bool {
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

    /// The rows and skips read off one screen, and whether the app is back on it.
    struct ScreenRead {
        let rows: [DiscoverClassifier.Row]
        let skipped: [DiscoverSkip]
        let returned: Bool
    }
}
