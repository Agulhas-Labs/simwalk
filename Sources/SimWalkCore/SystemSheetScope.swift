//
// Copyright © Agulhas Labs
//

import Foundation

/// Which part of the app's tree a `systemTap` may answer: only what appeared after the app last showed a screen of its own (SimWalk#28 review).
///
/// **A system sheet hosted in the app's window is in the app's tree** — HealthKit's authorization sheet is — so a label found there could as well be the app's own `Continue` or `Allow`. On a device that has already answered the sheet, or in a second state whose fresh launch is not asked again, nothing else is there to find, and tapping the app's control would record a system-sheet step that never happened. So the app's tree is read before the step that can raise the sheet — the *baseline*, whose timing `SystemSheetBaseline` owns — and a match counts only where it lies in a subtree the baseline did not have. Anything else is UNREACHABLE, naming the label, and naming the step ambiguous where the baseline already held a match (SimWalk#39).
///
/// **A node is placed by its path from the root, each step its type and identifier, never its label, value or frame.** A sheet presented over a screen moves and scales what it covers, and the app's own text changes as its data arrives; either, keyed in, would make the app's own control read as new, which is the one mistake this exists to prevent. The mistake it can make instead is the honest one: a sheet's control at a path the app's own screen already held is not admitted, and the step is UNREACHABLE.
public struct SystemSheetScope: Sendable {
    /// Every path in the baseline, and so every prefix of one: a node whose path is here was already on the app's own screen.
    private let known: Set<[PathStep]>
    /// The baseline itself, kept to say whether it already held what a step names.
    private let baseline: AXNode
    /// Whether this is the scope of a step the walkbook declares `atLaunch` (`admittingAll(of:)`), whose baseline held nothing but the root.
    private let declaredAtLaunch: Bool
    /// Whether the baseline is the launch's screen, read for a route's first step, where the walkbook could have declared the step `atLaunch` and did not.
    private let readAtLaunch: Bool

    /// A scope that admits only what `baseline` — the app's tree before any sheet could be up — did not hold.
    public init(baseline: AXNode) {
        self.init(baseline: baseline, declaredAtLaunch: false)
    }

    private init(baseline: AXNode, declaredAtLaunch: Bool, readAtLaunch: Bool = false) {
        known = Self.paths(in: baseline)
        self.baseline = baseline
        self.declaredAtLaunch = declaredAtLaunch
        self.readAtLaunch = readAtLaunch
    }

    /// A scope whose baseline is `tree`, the launch's screen, read for a route's first step that is not declared `atLaunch`: it admits what `init(baseline:)` does, and its ambiguous refusal names the declaration (SimWalk#39 item 2).
    public static func readAtLaunch(of tree: AXNode) -> Self {
        Self(baseline: tree, declaredAtLaunch: false, readAtLaunch: true)
    }

    /// The scope of a `systemTap` the walkbook declares `atLaunch`: its baseline is `tree`'s root with no children, so every subtree of the launch's screen is new (SimWalk#46).
    ///
    /// **An app that raises its sheet from its initialiser has no screen of its own without the sheet.** Read straight after `launch()`, the sheet is up before that read about half the time, and then its control reads as the app's own and the step is refused as ambiguous — the right answer for a match nobody declared, and one that admits such a route only by winning the race. The declaration is the author's word that the launch is the step that raised the sheet, so nothing of the launch's screen counts as the app's: the control is admitted wherever it lies, `scrollContainer` finds the sheet's list, and `closing` judges by the subtree holding the tapped control. What it gives up is the one check the baseline makes, so it is an author's claim and only a route's first step can make it (`WalkbookLoader`). Two limits follow. On a launch screen that is the app's own — the sheet late, or already answered — `scrollContainer` returns the app's list and the step drags it, and may tap the app's control: the declaration was wrong, and the manifest's `at launch` says on whose word. And a sheet hosted in the app's window never reads as closed under this scope, because `closing` judges by the new subtree holding the tapped control and the only one there is the window itself, which outlives the sheet: the step waits out the dismissal wait, and the scope stays in hand for the rest of the route.
    public static func admittingAll(of tree: AXNode) -> Self {
        var root = tree
        root.children = []
        return Self(baseline: root, declaredAtLaunch: true)
    }

    /// The outermost subtrees of `current` that the baseline did not have, in tree order.
    public func newSubtrees(of current: AXNode) -> [AXNode] {
        newRoots(of: current).map(\.node)
    }

    /// Whether `current` holds a subtree the baseline did not have: a sheet in the app's window (SimWalk#88).
    ///
    /// Never for a step declared `atLaunch`, whose baseline holds nothing of the app's, so every subtree is new and says nothing about a sheet.
    func showsSheet(in current: AXNode) -> Bool {
        !declaredAtLaunch && !newRoots(of: current).isEmpty
    }

    /// Whether the sheet `control` was taken from in `before` has closed by `after`: the subtree `before` held that the baseline did not, and that holds `control`, is no longer there (SimWalk#39).
    ///
    /// **The sheet, not the control.** HealthKit's `Continue` goes away when it opens the sheet's second page, and so does the control of a sheet that closed; only the second leaves nothing of the sheet behind. Placed by path like everything here: a second page at the path its first held reads as the sheet still up, which keeps the baseline, the side that can still admit the sheet's next control.
    ///
    /// **Only the sheet's own subtree** (the final review's finding 1). The baseline is read before the step that raised the sheet, so whatever else that step brought in — a page it pushed, a button that became a spinner — is new too, and outlives the sheet; judged by every new subtree, the sheet would never read as closed, and the app's own primer after it would be admitted as the sheet's. A subtree that arrived after `before` — that primer — neither keeps the sheet up nor is taken for it.
    ///
    /// **The subtree whose `control` has gone** (the third review's finding 1). `control` is found as `admits` finds it, by type, label and identifier, and the caller asks only once the tapped control has gone, so a new subtree whose every match `after` still holds at its path — a pushed page with a `Continue` just like the sheet's — is not the sheet, and never keeps it up. The frame cannot tell them apart: a remote sheet's snapshot frames are its own coordinates, 62 points off the live element's, so they would pick the page. Where more than one subtree has lost a match, the frontmost — last in tree order, as `scrollContainer` takes — is the sheet, presented over the rest. **Where none has**, the sheet has closed: that is the side that costs at most a false UNREACHABLE on the next `systemTap`, where keeping the baseline could admit the app's own primer (the third review's finding 2).
    public func hasClosed(sheetIn before: AXNode, holding control: AXNode, by after: AXNode) -> Bool {
        guard let sheet = sheetRoot(of: before, holding: control, by: after) else { return true }
        return !Self.paths(in: after).contains(sheet)
    }

    /// Whether the sheet `control` was tapped in has closed, read by read: `after` is the app's tree `elapsed` into the watch, begun once the tapped control went away.
    ///
    /// **Not from a single read** (the #39 review's finding 3). The control goes before its sheet's container has finished animating out, and a container still up reads as the sheet still up, which would keep the old baseline and admit the app's own primer behind it. So a sheet still up is read again until `wait` has passed — the time a tapped control is given to go — and only then answered as up, which a sheet that stays (`Continue` to its second page) costs once.
    public func closing(sheetIn before: AXNode, holding control: AXNode, by after: AXNode, elapsed: TimeInterval, within wait: TimeInterval) -> SheetClosing {
        if hasClosed(sheetIn: before, holding: control, by: after) {
            return .closed
        }
        return elapsed < wait ? .readAgain : .stillUp
    }

    /// Whether `tree` still holds `control`: a node of its type, label and identifier anywhere in it, as `admits` finds one — the runner's judgement that a tapped control has gone, read from a snapshot rather than the element bound by index (SimWalk#47).
    ///
    /// **Never by the frame**: a remote sheet reports its content in its own coordinates, so the tapped control's box need not be where the tree puts it. A tap that changes the control's label leaves it no longer held, and whether its sheet has closed is `closing`'s question, not this one.
    public static func holds(_ control: AXNode, in tree: AXNode) -> Bool {
        var found = false
        visit(tree, under: []) { node, _ in
            found = found || isSameControl(node, as: control)
            return !found
        }
        return found
    }

    /// Whether `tree` still holds the sheet's `control` that was tapped in the app's window: `admits` asked again, so a control of the same type, label and identifier that the app's own screen keeps does not read as the sheet's still up (the #47 review).
    ///
    /// **Not `holds`**, which matches anywhere in the tree: where the app's window keeps a control identical to the sheet's — a page with its own `Continue` — the sheet's goes and `holds` stays true, the tap reads as never landed, the sheet is never judged closed, and the next `systemTap` is judged against a baseline that admits the app's own primer as fresh (SimWalk#39). `admits` breaks that tie by the frame, which it can here: `control` carries its snapshot frame, the tree's own coordinate space. SpringBoard's alerts have no scope, so their controls keep `holds`.
    public func stillHolds(_ control: AXNode, in tree: AXNode) -> Bool {
        admits(control, in: tree)
    }

    /// Why a `systemTap` for `label` found nothing it could take: what its UNREACHABLE says.
    ///
    /// **Ambiguous when the baseline already held a match** (SimWalk#39). Where that baseline was the launch's screen, the refusal names the fix, `"atLaunch":true` on the route's first step (SimWalk#46), since a sheet the launch raises races that read and the tree cannot say it lost (#39 item 2). A match already in it is the app's own control or a sheet up before that read — a sheet asked for from the app's first task, when the route begins with a `systemTap` and the read is the launch's — and the tree cannot say which. So the step says that, rather than a bare "no control", and taps neither; it keeps the hint that a sheet already answered is not asked again, the likeliest reading on a device that has answered. `passedOverAppOwn` is a match seen while polling that was not admitted, at a path the app's own screen already held.
    ///
    /// **A step declared `atLaunch` names its declaration instead** (SimWalk#46): its baseline held nothing of the app's, so no match was passed over as the app's own, and what is left to say is that nothing the walkbook said would be there was. On a fresh boot it does not claim the app's window showed no sheet (SimWalk#90 item 4): `showsSheet(in:)` is always false for it, so only SpringBoard can count as a sheet seen, and a sheet up with a mistyped label looks the same; it says the tree cannot tell, gives the boot's age, and asks for the label to be checked.
    ///
    /// **Where no sheet showed at all on a device that booted under ``freshBoot`` ago, the boot is named instead of an answered sheet** (SimWalk#88). HealthKit raised no sheet on a freshly booted simulator for its first minutes — twice on devices walked about 70 s after they were created, once on one the walk itself cold-booted — and the same walk passed on the same device two minutes later. "Already answered" sends an agent to erase the device, which restarts the wait. `bootAge` is the seconds since the device booted, `nil` where that is unknown, which keeps the answered-sheet hint; the ambiguous refusal keeps it whatever the age, since a match was there.
    ///
    /// **Not "none" where SpringBoard showed an alert** (SimWalk#91). `springBoardShowedAlert` is that the step saw one, whether or not it held the label: the refusal then says so, and drops the boot age, since a device that raised an alert is not one that raised nothing. And an `atLaunch` refusal, fresh boot or not, never claims the app's window showed no sheet, for the reason above: the tree cannot back it.
    public func refusal(for label: String, passedOverAppOwn: Bool, bootAge: TimeInterval? = nil, springBoardShowedAlert: Bool = false, appWindowShowedSheet: Bool = false) -> String {
        let bootAge = springBoardShowedAlert ? nil : bootAge
        let noSheet = Self.noSheetHint(bootAge: bootAge)
        if declaredAtLaunch {
            let launch = "no enabled control '\(label)' on the launch's screen, which the walkbook declares a system sheet's — "
            let springBoard = springBoardShowedAlert ? "SpringBoard showed an alert with no enabled '\(label)'" : "SpringBoard showed no alert SimWalk could read"
            let appWindow = ", and the tree cannot say whether one showed in the app's window at launch; "
            if let age = Self.freshBootAge(bootAge) {
                return launch + springBoard + appWindow + "\(Self.freshBootAdvice(age)), or the label may not match the sheet's control: check it"
            }
            return launch + springBoard + appWindow + noSheet
        }
        let none = "no enabled control '\(label)' on a system sheet"
        if baseline.flattened.contains(where: { Self.answers(label, $0) }) {
            let declare = readAtLaunch ? "; if the launch raises this sheet, declare it on the route's first step: {\"systemTap\":{\"label\":\(Self.jsonString(label)),\"atLaunch\":true}}" : ""
            return "\(none) that was not already on screen — ambiguous: a '\(label)' was in the app's tree when it was read before the sheet could be up, the app's own control or a system sheet already up, and SimWalk cannot tell which, so it tapped neither; a sheet already answered is not asked again\(declare)"
        }
        let appOwn = passedOverAppOwn ? "; a '\(label)' was there but was present when the app's screen was last read, so it was not taken for a system sheet's" : ""
        let appWindow = appWindowShowedSheet ? "the sheet in the app's window held none" : "no sheet in the app's window held one"
        let shown = if springBoardShowedAlert {
            "SpringBoard showed an alert with no enabled '\(label)', and \(appWindow)"
        } else if appWindowShowedSheet {
            "SpringBoard showed no alert SimWalk could read, and \(appWindow)"
        } else {
            "neither SpringBoard nor a sheet in the app's window showed one"
        }
        return "\(none) — \(shown)\(appOwn); \(noSheet)"
    }

    /// How long after a boot a simulator counts as freshly booted, in seconds: within it, a step that saw no system sheet names the boot rather than an answered sheet (SimWalk#88).
    ///
    /// Measured, not derived: walks within about 70 s of a boot saw no HealthKit sheet, and one about two minutes later on the same device saw it; on a device erased and booted again, a walk 261 s after the boot still saw none and one at about 377 s did. Ten minutes covers that with room, because the two mistakes are not equal: a wrong "wait" costs one more walk, a wrong "already answered" sends an agent to erase the device and start the wait again.
    public static var freshBoot: TimeInterval {
        600
    }

    /// What a refusal that saw no system sheet ends with: the boot's age where the device booted under ``freshBoot`` ago, else that a sheet already answered is not asked again.
    private static func noSheetHint(bootAge: TimeInterval?) -> String {
        guard let age = freshBootAge(bootAge) else {
            return "a sheet already answered is not asked again"
        }
        return freshBootAdvice(age)
    }

    /// `bootAge` where it falls within ``freshBoot``, else `nil`.
    private static func freshBootAge(_ bootAge: TimeInterval?) -> TimeInterval? {
        guard let bootAge, (0 ..< freshBoot).contains(bootAge) else {
            return nil
        }
        return bootAge
    }

    /// The boot's age and what to do about it.
    private static func freshBootAdvice(_ age: TimeInterval) -> String {
        "the device booted \(Int(age.rounded())) s ago, and HealthKit raises no sheet on a freshly booted simulator for its first minutes — wait and walk again on the same device; erasing or rebooting it restarts the wait"
    }

    /// `text` as a JSON string literal, quotes and backslashes escaped, so a declaration the refusal names pastes in as written.
    private static func jsonString(_ text: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        guard let data = try? encoder.encode(text), let literal = String(data: data, encoding: .utf8) else {
            return "\"\(text)\""
        }
        return literal
    }

    /// Why a `systemTap` for `label` found nothing it could take, from everything its polls passed over.
    ///
    /// **A live match the tree read does not hold is a fact about the read, not the sheet** (SimWalk#48). A remote sheet's content — HealthKit's, hosted by `com.apple.HealthPrivacyService` — is in `app.snapshot()` only on the first app launch after its host process starts; on every later launch the snapshot stops where the remote view is hosted, while the live query still finds the control, enabled and hittable. Nothing judged from the tree can admit it then, and the plain refusal would say no control was there. So where the last poll that found a live match found the tree holding none of it, the refusal says the snapshot cannot see it and what clears it, ahead of anything the tree would have said.
    func refusal(for label: String, passedOver: PassedOver, bootAge: TimeInterval?, springBoardShowedAlert: Bool = false, appWindowShowedSheet: Bool = false) -> String {
        guard passedOver.unseenByTree else {
            return refusal(for: label, passedOverAppOwn: passedOver.appOwn, bootAge: bootAge, springBoardShowedAlert: springBoardShowedAlert, appWindowShowedSheet: appWindowShowedSheet)
        }
        return "a '\(label)' is on screen and reachable, and the app's snapshot does not hold it — most likely a remote sheet the snapshot cannot see (HealthKit's is hosted by com.apple.HealthPrivacyService); terminate the sheet's host process (xcrun simctl terminate <udid> <host bundle id>) or reboot, and walk again"
    }

    /// Whether `element` — its type, label, identifier and frame as the element's own snapshot reports them — lies in `current` in a subtree the baseline did not have.
    ///
    /// **Found by type, label and identifier; the frame only breaks a tie.** A sheet hosted as a remote view reports its content's frames in its own coordinate space in a snapshot — measured on HealthKit's, iOS 27.0: a cell the live element puts at y 403 reads 341 in `app.snapshot()`, the sheet's own origin 62 points down — so a frame cannot find the element. It can only tell two candidates apart: where the app's own screen holds a control of the same type, label and identifier, the element is admitted only if its frame is a new one's and not the app's. That comparison needs `element`'s frame in the tree's own space, which is why it is the element's snapshot frame and not its live one: measured on the same sheet (SimWalk#47 review), `UIA.Health.AuthSheet.AllCategoryButton` reads y 341 in its own `snapshot()` and in `app.snapshot()`, and y 407.05 live. An element `current` does not hold at all, read a moment later from a tree that moved, is not admitted — the next poll reads both again.
    func admits(_ element: AXNode, in current: AXNode) -> Bool {
        var fresh: [AXNode] = []
        var old: [AXNode] = []
        Self.visit(current, under: []) { node, path in
            if Self.isSameControl(node, as: element) {
                if known.contains(path) {
                    old.append(node)
                } else {
                    fresh.append(node)
                }
            }
            return true
        }
        guard !fresh.isEmpty else { return false }
        guard !old.isEmpty else { return true }
        return fresh.contains { Self.isSameBox($0, as: element) } && !old.contains { Self.isSameBox($0, as: element) }
    }

    /// The scroll container a sheet's control below the fold is brought on screen in: the frontmost one — last in tree order — among the subtrees the baseline did not have, or `nil` when no sheet brought one.
    ///
    /// **Never the app's own list.** A drag on it before a slow sheet arrives moves the screen the walk is on, so a container is evidence of a sheet only when it is new. Its path is returned with it, so a caller can tell a later sheet's container from one it has already scrolled.
    public func scrollContainer(in current: AXNode) -> ScrollTarget? {
        var target: ScrollTarget?
        Self.visit(current, under: []) { node, path in
            if !known.contains(path), Self.scrollTypes.contains(node.type) {
                target = ScrollTarget(node: node, path: path.map(\.rendered).joined(separator: "/"))
            }
            return true
        }
        return target
    }

    /// The outermost subtrees of `current` that the baseline did not have, each with its path, in tree order.
    private func newRoots(of current: AXNode) -> [(node: AXNode, path: [PathStep])] {
        var found: [(node: AXNode, path: [PathStep])] = []
        Self.visit(current, under: []) { node, path in
            guard known.contains(path) else {
                found.append((node, path))
                return false
            }
            return true
        }
        return found
    }

    /// The path of the new subtree of `before` that `control` was tapped in: the frontmost one holding a match that `after` no longer holds, or `nil` where none does.
    private func sheetRoot(of before: AXNode, holding control: AXNode, by after: AXNode) -> [PathStep]? {
        let stillThere = Self.matchPaths(of: control, in: after, under: [])
        return newRoots(of: before).last { root in
            !Self.matchPaths(of: control, in: root.node, under: Array(root.path.dropLast())).isSubset(of: stillThere)
        }?.path
    }

    /// The paths of the nodes in `tree` that are the same control as `control`, `tree` itself at a path under `parent`.
    private static func matchPaths(of control: AXNode, in tree: AXNode, under parent: [PathStep]) -> Set<[PathStep]> {
        var found = Set<[PathStep]>()
        visit(tree, under: parent) { node, path in
            if isSameControl(node, as: control) {
                found.insert(path)
            }
            return true
        }
        return found
    }

    /// Every path in `tree`, and so every prefix of one.
    private static func paths(in tree: AXNode) -> Set<[PathStep]> {
        var paths = Set<[PathStep]>()
        visit(tree, under: []) { _, path in
            paths.insert(path)
            return true
        }
        return paths
    }

    /// Whether `node` answers `label` as the runner's live query does: the whole label, the identifier, or the leading comma-separated component of a composed label.
    private static func answers(_ label: String, _ node: AXNode) -> Bool {
        node.label == label || node.identifier == label || node.label?.hasPrefix("\(label), ") == true
    }

    /// Walks `node` in tree order with each node's path, descending wherever `body` answers `true`.
    private static func visit(_ node: AXNode, under parent: [PathStep], _ body: (AXNode, [PathStep]) -> Bool) {
        let path = parent + [PathStep(type: node.type, identifier: node.identifier)]
        guard body(node, path) else { return }
        for child in node.children {
            visit(child, under: path, body)
        }
    }

    /// Whether `tree` holds `control` at its own box, not merely a control of the same type, label and identifier elsewhere.
    ///
    /// A remote sheet's `Allow` must not read as held because the app's own `Allow` is. `control`'s frame is its own snapshot's, the tree's coordinate space.
    static func holdsInPlace(_ control: AXNode, in tree: AXNode) -> Bool {
        var found = false
        visit(tree, under: []) { node, _ in
            found = found || (isSameControl(node, as: control) && isSameBox(node, as: control))
            return !found
        }
        return found
    }

    private static func isSameControl(_ node: AXNode, as element: AXNode) -> Bool {
        node.type == element.type && node.label == element.label && node.identifier == element.identifier
    }

    private static func isSameBox(_ node: AXNode, as element: AXNode) -> Bool {
        abs(node.frame.x - element.frame.x) <= 1
            && abs(node.frame.y - element.frame.y) <= 1
            && abs(node.frame.width - element.frame.width) <= 1
            && abs(node.frame.height - element.frame.height) <= 1
    }

    /// The element types a sheet scrolls its content in.
    static let scrollTypes: Set<String> = ["Table", "CollectionView", "ScrollView"]
}

public extension SystemSheetScope {
    /// What one read after a tap says of the sheet the control was in (`closing`).
    enum SheetClosing: Equatable, Sendable {
        /// Nothing the sheet brought is left.
        case closed
        /// Some of it is still there and the wait is not spent: pause and read again.
        case readAgain
        /// Still there once the wait is spent: the sheet stayed up.
        case stillUp
    }

    /// What a `systemTap`'s polls found live and did not take, for `refusal(for:passedOver:)` to say (SimWalk#48).
    ///
    /// **Judged on the last poll that found a live match**, not on any one: a tree read a moment before the live query can miss a row a decelerating table has just turned into a `Button`, and one such poll is a race, not a snapshot that cannot see the sheet. A remote sheet's content missing from every read stays missing on the last.
    struct PassedOver: Equatable, Sendable {
        /// A live match the tree held but the scope did not admit, at a path the app's own screen already had.
        public private(set) var appOwn = false
        /// Whether any of the last poll's live matches was missing from its tree read — the snapshot, not the sheet, lacking it.
        ///
        /// Any, not all: the app's own control of the same label, held and hittable beside a remote sheet's, must not hide the sheet's from the refusal (the 2026-09-23d review).
        public private(set) var unseenByTree = false

        public init() {}

        /// Notes one poll: `live` is every match its live query reached and did not take, each as its own snapshot reports it; `tree` is the app's tree read in that poll.
        public mutating func poll(_ live: [AXNode], in tree: AXNode) {
            guard !live.isEmpty else { return }
            let held = live.filter { SystemSheetScope.holdsInPlace($0, in: tree) }
            appOwn = appOwn || !held.isEmpty
            unseenByTree = held.count < live.count
        }
    }

    /// A new scroll container, and the path that tells it from another.
    struct ScrollTarget: Equatable, Sendable {
        /// The container as the tree read it, frame included, for the runner to bind to the live element.
        public let node: AXNode
        /// Its path from the root, as `type#identifier` steps.
        public let path: String
    }
}

extension SystemSheetScope {
    /// One step of a node's path: what it is and the identifier the app gave it, nothing that changes with content.
    struct PathStep: Hashable, Sendable {
        let type: String
        let identifier: String?

        var rendered: String {
            identifier.map { "\(type)#\($0)" } ?? type
        }
    }
}
