//
// Copyright © Agulhas Labs
//

import SimWalkCore
import UIKit
import XCTest

/// Executes one route step on the app as it stands — the only code that does, for a walk, a dry run, and anything else that takes a step.
///
/// **One performer, so a step means one thing wherever it is taken.** `WalkRunner.follow` makes one for every step of a route, in a walk and a dry run alike; a step taken anywhere else goes through the same type and the same `perform`, so what a label matches and whether a step landed cannot drift between the places a step is taken (SimWalk#1 item 4).
///
/// **Made per step**, because what it holds is the step's own: the quiet period of the screen the step is taken on, the destination's budget, and the `systemTap` scope and reads `SystemSheetBaseline` hands that step. The timing constants a step waits by are its statics.
///
/// `@MainActor` for the reason `WalkRunner` is: XCUITest drives the app from the main thread and `snapshot()` hands back a non-`Sendable` value there.
@MainActor
struct StepPerformer {
    /// The app the step is taken in.
    let app: XCUIApplication
    /// The quiet period of the screen the step is taken on (`SettleWindow.quiet(forStep:of:in:default:)`).
    let quiet: TimeInterval
    /// The destination screen's settle budget.
    let budget: TimeInterval
    /// What a `systemTap` admits of the app's tree, as `SystemSheetBaseline` scoped it for this step; `nil` makes one from the step's first read.
    let sheetScope: SystemSheetScope?
    /// The app's tree as a `systemTap` judges it — one per step (`WalkRunner.SheetReads`).
    let sheetReads: WalkRunner.SheetReads
    /// When the step was seen to arrive, for the capture's motion record (`CaptureManifest.Motion.landingMilliseconds`); written by the two arrival waits, so a step that does not wait for arrival leaves it empty.
    let arrival = Arrival()

    /// Executes one route step, answering whether it landed rather than failing the test.
    ///
    /// **A step that navigates is waited on, and that is the fix for the worst thing this tool has done.** A `tap` that pushes a detail view returns the instant the touch is delivered; the screen it left then holds perfectly still, so the settle window closed on *it* and its screenshot and tree were filed under the target screen's id with outcome `captured`. The manifest said the screen was reached; the picture was of somewhere else, and nothing in the bundle could tell (SimWalk#6). So `tap` and `back` now wait for the hierarchy to leave the screen they were taken on, and report the step as not landed if it never does.
    ///
    /// **A screen identity rather than a longer timer**, because a raised default would paper over the same defect at three times the cost of every walk and a slow machine would defeat it again. `ScreenIdentity` carries no timing assumption at all.
    ///
    /// **`tab` is the one exception, and it is a real one.** A walkbook's first step routinely names the tab the app launches on — `progress-day` in a field walkbook is exactly `[tab 'Progress']` — and nothing has to change for that step to have landed. So a tab already selected is landed untouched (SimWalk#106): it is not tapped, since iOS pops a tab's stack to its root on a tap of the tab it is on, and a screen a launch argument pushed would be gone before capture. The hittable check still runs first, so a covered tab is refused. A tab that was not selected has to move the hierarchy like anything else. The tab is looked for in the tree every interval until `TabTarget` finds it or the timeout passes, on a `TabBar` or on iPad's floating tab bar (SimWalk#109).
    ///
    /// **A `tap` resolves its label among every element carrying it, ranked (SimWalk#17)** — a control above content above chrome — rather than taking the first in tree order, which on a screen titled with the same word is the navigation bar. `RouteTarget` makes that choice, in the core where a test can hold it; this reads the screen until `RouteTargetTracker` says the answer cannot improve, and taps what it chose. A step that does not land says what its label matched.
    ///
    /// **`scrollTo` and `type` resolve through the same choice**, so a label matches the same way in every step that takes one — the same tiers, a `{n}` pattern, a lead-in to a label's data, a refusal on a tie between lead-ins. What each reaches for differs (`RouteTarget.Reach`), and so, sometimes, does where it lands: `scrollTo X` then `tap X` can arrive at different elements, because a scroll never prefers a bar's control to content — `scrollTo 'Workouts'` goes to the card, and `tap 'Workouts'` to the tab item beside it.
    ///
    /// **A `tap` or `scrollTo` whose label resolves to nothing swipes before it gives up** (SimWalk#74, and a `tap` since SimWalk#104, because one route has to work across a screen's states and Dynamic Type moves rows below the fold of a lazy list; `type` does not): a lazy list has not built the row yet, so the step swipes and reads again until something carries the label, then resolves it as above. `ScrollSearch` decides each move and, when the swipes stop short, says why — the end of the list, or the most swipes a step takes — naming the label and the swipes taken.
    ///
    /// **A `scrollTo` lands only once no bar in front covers its element** (SimWalk#108): XCUITest calls an element hittable while the floating tab bar is over half of it, so after the search finds it the step nudges the content until its frame clears every tab bar, toolbar and navigation bar that is hittable over it, and is UNREACHABLE where it cannot. A target that is a bar or sits in one — a tab item — lands as it always did. A `tap` whose label the seek swiped into the tree is cleared the same way before it taps, since that row sits at the fold, under the tab bar (SimWalk#104). `ScrollClearance` decides each nudge.
    ///
    /// **A spacing match, a `{n}` pattern or a lead-in that has moved on is chosen again, once** (`RouteTarget.Choice.rebinding`): such an element is bound by the label the snapshot recorded, and the labels those matches exist for are the ones that tick between the read and the bind. The same element at its new label is bound; a different one is never acted on silently.
    ///
    /// **`quiet` is the quiet period of the screen the step is taken on** (`SettleWindow.quiet(forStep:of:in:default:)`); `budget` is the destination screen's, as it always was.
    func perform(_ step: Walkbook.RouteStep) throws -> StepResult {
        switch step {
        case let .tab(label):
            // SimWalk#109: the tab is found in the tree, because on iPad the floating tab bar is no `TabBar`
            // node; `TabTarget` says where, and the live button is bound by that node's label and frame.
            // One deadline for finding and rebinding, so a tab waits `Self.timeout` for both, not twice over.
            let stepDeadline = Date().addingTimeInterval(Self.timeout)
            let located = try TabLocator.locate(label, in: app, until: stepDeadline)
            let node: AXNode
            switch located {
            case let .found(found, _):
                node = found
            case let .missing(tabs, bar):
                return .blocked(reason: TabStepRefusal.notFound(label: label, tabs: tabs, bar: bar))
            }
            // By identifier as well, as the old `tabBars.buttons[label]` subscript bound: `TabTarget` matches either.
            // A failed bind locates again from a fresh read and rebinds until the deadline, because a floating
            // bar still animating in has a frame that is gone by the time the first read is bound; the old
            // `waitForExistence` + `tap` waited that out.
            let predicate = NSPredicate(format: "label == %@ OR identifier == %@", label, label)
            var bindNode = node
            var bound: XCUIElement?
            while true {
                bound = app.buttons.matching(predicate).allElementsBoundByIndex
                    .first { TargetResolution.frame($0.frame, matches: bindNode.frame) }
                guard bound == nil, Date() < stepDeadline else { break }
                Thread.sleep(forTimeInterval: Self.settleInterval)
                if case let .found(fresh, _) = try TabTarget.locate(label, in: AXTreeCapture.tree(of: app)) {
                    bindNode = fresh
                }
            }
            guard let element = bound else {
                return .blocked(reason: "the tab '\(label)' moved before it could be tapped")
            }
            // SimWalk#95: a modal over the app left `isSelected` true (or the tree changing under a tap that
            // never reached the bar), so `landed` proved nothing about the app being in front. A button
            // that exists but cannot be hit is covered; refuse before either path can pass.
            // Polled, not read once: attribute reads do not wait for idle as `tap()` did, and the previous
            // step can land while the bar is still sliding or fading in. `isHittable` is read through
            // `liveRead` because it records "Activation point invalid" on an element mid-transition. The cost
            // falls on a covered tab only: it is refused after `Self.timeout` (10 s) of polling, on top of the
            // one 10 s deadline that `locateTab` and the rebind share above; a hittable tab passes on the first read.
            let hittableDeadline = Date().addingTimeInterval(Self.timeout)
            var hittable = Self.liveRead(or: false) { element.isHittable }
            while !hittable, Date() < hittableDeadline {
                Thread.sleep(forTimeInterval: Self.settleInterval)
                hittable = Self.liveRead(or: false) { element.isHittable }
            }
            // SimWalk#95 and #106 are decided in the core (`TabStepAction`): a covered tab is refused whatever
            // it reports as selected, a selected one is landed on untouched, any other is tapped.
            switch TabStepAction.decide(label: label, hittable: hittable, selected: hittable && Self.liveRead(or: false) { element.isSelected }) {
            case let .refuse(reason):
                return .blocked(reason: reason)
            case .landUntouched:
                return .landed
            case .tap:
                break
            }
            let departed = try ScreenIdentity.of(AXTreeCapture.tree(of: app))
            element.tap()
            return try StepResult(arrived(leaving: departed, in: app, budget: budget))
        case let .tap(label):
            // A label the tree does not hold yet is swiped towards, as `scrollTo` does (SimWalk#104).
            var search = ScrollSearch(label: label, limit: Self.scrollAttempts)
            let (choice, stopped) = try TargetResolution.resolveSeeking(label, reaching: .control, search: &search, in: app, quiet: quiet, budget: budget)
            if let stopped {
                return .blocked(reason: stopped)
            }
            guard case .chosen = choice else {
                return .blocked(reason: choice.reason(for: label))
            }
            let binding = try TargetResolution.bind(choice, labelled: label, in: app, quiet: quiet, budget: budget) {
                TargetResolution.element(for: $0, labelled: label, in: app)
            }
            guard case let .element(element, target, bound) = binding else {
                return .blocked(reason: binding.refusal(doing: "tapped"))
            }
            // A row the seek swiped into the tree sits at the fold, under the tab bar a tap there would land on.
            if search.swipes > 0, case let .blocked(reason, _) = try BarClearance.clearOfBars(element, as: target, in: app) {
                return .blocked(reason: reason)
            }
            let before = try AXTreeCapture.tree(of: app)
            let departed = ScreenIdentity.of(before)
            // A keyboard key is judged by the focused field as well (SimWalk#94): a keystroke changes that
            // field's value and nothing `ScreenIdentity` hashes, so identity alone refused every digit
            // typed on a number pad that had in fact landed. A Return exposed as a button inside the keyboard
            // is a key too (SimWalk#96), which is why the core decides it from the tree.
            guard TypedTextLanding.isKey(target.node, in: before) else {
                // SimWalk#125 and #95 are decided in the core (`TapLanding`): an element selected in the snapshot
                // and live, hittable now, under a navigation bar naming the label in the tree read above, has landed
                // even if the tap changes nothing, its destination already on screen (an iPad sidebar row opened
                // selected). The live reads go through `liveRead`, as the `tab` step's do, and only for an element
                // the snapshot read as selected, the one case they decide: a covered element reads false and is
                // refused as before, and every other tap is spared a live query.
                // Hittability is polled to a short deadline, as the tab path's is: a row can be read while the
                // screen is still settling, and one read would call it covered (SimWalk#126).
                let selected = target.node.isSelected && Self.liveRead(or: false) { element.isSelected }
                var hittable = selected && Self.liveRead(or: false) { element.isHittable }
                let hittableDeadline = Date().addingTimeInterval(Self.selectedHittableWait)
                while selected, !hittable, Date() < hittableDeadline {
                    Thread.sleep(forTimeInterval: Self.settleInterval)
                    hittable = Self.liveRead(or: false) { element.isHittable }
                }
                element.tap()
                let landing = try TapLanding.decide(
                    arrived: arrived(leaving: departed, in: app, budget: budget),
                    wasSelected: selected,
                    hittable: hittable,
                    titled: TapLanding.destinationTitled(label: label, in: before, tapped: target.node)
                )
                return landing == .notLanded ? .blocked(reason: bound.reason(for: label)) : .landedOn(target.node)
            }
            let focusedBefore = Self.focusedFieldValue(in: app)
            element.tap()
            let landed = try keyLanded(leaving: departed, focusedBefore: focusedBefore, in: app, budget: budget)
            return landed ? .landedOn(target.node) : .blocked(reason: bound.keyReason(for: label, fieldHadFocus: focusedBefore != .none || Self.focusedFieldValue(in: app) != .none))
        case let .type(label, text):
            // Resolved among text-entry elements only. The first node in tree order carrying the label
            // is routinely the container a search field is drawn inside — and `typeText` on a container
            // is an *XCTest failure*, which fails the whole walk rather than returning something this
            // loop could report as a step that did not land.
            let choice = try TargetResolution.resolve(label, reaching: .textEntry, in: app, quiet: quiet, budget: budget)
            guard case .chosen = choice else {
                return .blocked(reason: choice == .none ? nil : choice.reason(for: label))
            }
            let binding = try TargetResolution.bind(choice, labelled: label, in: app, quiet: quiet, budget: budget) {
                TargetResolution.textEntry(for: $0, in: app)
            }
            guard case let .element(element, target, _) = binding else {
                return .blocked(reason: binding.refusal(doing: "typed into"))
            }
            // Read before the field is touched, because an empty field reports its *placeholder* as its
            // value — so `type 'terms' into 'Search items, examples, terms…'` would read back a value
            // containing the text without a keystroke having landed. The evidence is the change.
            let before = element.value as? String
            element.tap()
            element.typeText(text)
            // The honest post-condition, and it is the field's own value rather than the keyboard's
            // presence. Waiting for the keyboard was the first attempt and is not dependable: on this
            // iOS it belongs to another process, so `app.keyboards` timed out evaluating the query
            // against both a real app and Settings — and a simulator with a hardware keyboard attached
            // never shows a software one at all, which would have reported every honest `type` step as
            // not having landed.
            let typed = TypedTextLanding.landed(
                text: text,
                before: before,
                after: element.value as? String,
                redactedValue: element.elementType == .secureTextField
            )
            return typed ? .landedOn(target.node) : .blocked(reason: nil)
        case let .scrollTo(label):
            // Swipes until the element is actually on screen, and reports failure if it never gets
            // there. The first version swiped **once and returned true regardless**, which meant a
            // target three swipes down was captured at whatever scroll position one swipe reached —
            // silently, and labelled as though the step had succeeded. Same class as the dark-mode
            // bug: a claim about the screenshot that nothing in the bundle can check.
            //
            // Swipe, then resolve (SimWalk#74): a lazy list builds no row below the fold, so a label that
            // resolves to nothing is swiped towards and read again before the step gives up, and every
            // give-up names the label, the swipes and why they stopped (`ScrollSearch`).
            //
            // Hittable is not clear (SimWalk#108): once found, the element is nudged out from under any bar
            // in front of it, or the step refuses (`ScrollClearance`), so a capture never reads `captured`
            // with its target behind the tab bar. A tab item or other bar control is landed on as it is.
            var search = ScrollSearch(label: label, limit: Self.scrollAttempts)
            let (choice, stopped) = try TargetResolution.resolveSeeking(label, reaching: .anything, search: &search, in: app, quiet: quiet, budget: budget)
            if let stopped {
                return .blocked(reason: stopped)
            }
            guard case .chosen = choice else {
                return .blocked(reason: choice.reason(for: label))
            }
            let binding = try TargetResolution.bind(choice, labelled: label, in: app, quiet: quiet, budget: budget) {
                TargetResolution.element(for: $0, labelled: label, in: app)
            }
            guard case let .element(element, target, _) = binding else {
                return .blocked(reason: binding.refusal(doing: "scrolled to"))
            }
            // The bound element is read afresh at every access, and an index can name a later row once a
            // lazy list recycles the ones above; so each read checks it is still the element chosen
            // (`RouteTarget.Candidate.isStill`) before it can count as arrived.
            while true {
                guard Self.isStill(element, as: target) else {
                    return .blocked(reason: "\(target.description) was lost while scrolling to it: what is bound in its place no longer carries its label at its size")
                }
                switch try search.reach(target, in: AXTreeCapture.tree(of: app), hittable: element.isHittable) {
                case .swipe:
                    app.swipeUp()
                case .found:
                    return try BarClearance.clearOfBars(element, as: target, in: app)
                case let .stopped(_, reason):
                    return .blocked(reason: reason)
                }
            }
        case let .tapPoint(label, point):
            return try tapPoint(at: point, within: label, in: app, quiet: quiet, budget: budget)
        case let .systemTap(label, atLaunch, _):
            let scope = try sheetScope ?? SystemSheetScope(baseline: sheetReads.appTree())
            return try systemTap(label, atLaunch: atLaunch, over: app, reading: sheetReads, admitting: scope)
        case let .openURL(url):
            guard let target = URL(string: url) else { return .blocked(reason: nil) }
            let departed = try ScreenIdentity.of(AXTreeCapture.tree(of: app))
            // A web link goes through the system so a universal link routes as it would from outside the app;
            // the app's own scheme is handed to the walked app, which `open` brings forward if need be.
            if let scheme = target.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                XCUIDevice.shared.system.open(target)
            } else {
                app.open(target)
            }
            return try openedURLArrived(leaving: departed, in: app, budget: budget)
        case .back:
            let back = app.navigationBars.buttons.firstMatch
            guard back.waitForExistence(timeout: Self.timeout) else { return .blocked(reason: nil) }
            let departed = try ScreenIdentity.of(AXTreeCapture.tree(of: app))
            back.tap()
            return try StepResult(arrived(leaving: departed, in: app, budget: budget))
        }
    }

    /// Taps a point — within the frame of the element `label` resolves to, or on the screen when there is no label (SimWalk#29).
    ///
    /// **The label resolves through the same choice as every other step's** (`resolve`, then `bind`), reaching as a `scrollTo` does: a chart is content, not a control, and a bar's control is never preferred to it. What it contributes is only a frame; `TapPointPlacement` decides the point, or refuses — an empty frame, a point off the screen — in the core where a test holds it.
    ///
    /// **Landed means the touch was delivered there and, if it navigated, that the destination was reached** (SimWalk#29 review, item 1) — a `tap` that pushes returns before the push happens, so the same wait `tap` and `back` already pay is what this step now pays too, or SimWalk#6 recurs one step over: the settle window closes on the screen just left, filing its capture under the destination's id, and the next route step resolves against the wrong screen. So the step waits one quiet period after the touch, and then lands unconditionally: no read of the tree lands it early, since `ScreenIdentity` cannot tell a push from a ticking label, a spinner or a callout (the 2026-09-23 review), and nothing after the touch refuses (SimWalk#38, item 4). `TapPointLanding` holds the decision and the wait, in the core, where a test replays it against a scripted clock (SimWalk#38); this loop keeps only the clock. The manifest still names the step `tapPoint`, so a reader can tell what resolved it.
    private func tapPoint(at point: [Double], within label: String?, in app: XCUIApplication, quiet: TimeInterval, budget: TimeInterval) throws -> StepResult {
        var element: AXNode.Frame?
        if let label {
            let choice = try TargetResolution.resolve(label, reaching: .anything, in: app, quiet: quiet, budget: budget)
            guard case .chosen = choice else {
                return .blocked(reason: choice.reason(for: label))
            }
            let binding = try TargetResolution.bind(choice, labelled: label, in: app, quiet: quiet, budget: budget) {
                TargetResolution.element(for: $0, labelled: label, in: app)
            }
            guard case let .element(_, target, _) = binding else {
                return .blocked(reason: binding.refusal(doing: "tapped within"))
            }
            element = target.node.frame
        }
        let bounds = app.frame
        let screen = AXNode.Frame(x: bounds.origin.x, y: bounds.origin.y, width: bounds.size.width, height: bounds.size.height)
        switch TapPointPlacement.of(point, within: element, onScreen: screen) {
        case let .refused(reason):
            return .blocked(reason: reason)
        case let .point(x, y):
            // One of this walk's quiet periods, not the fixed poll interval: a walk slowed with `--settle` is one
            // whose pushes take that long to reach the tree (SimWalk#29 review 2).
            let landing = TapPointLanding(quiet: quiet)
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x - screen.x, dy: y - screen.y)).tap()
            let touched = Date()
            while true {
                switch landing.next(elapsed: Date().timeIntervalSince(touched)) {
                case .watch:
                    Thread.sleep(forTimeInterval: Self.settleInterval)
                case .landed:
                    return .landed
                }
            }
        }
    }

    /// Taps a control on a system sheet: SpringBoard's first, then one hosted in the app's own window (SimWalk#28).
    ///
    /// **Which process draws the sheet was found, not assumed** (2026-09-22, iOS 27.0): the notifications alert is SpringBoard's, and HealthKit's authorization sheet is a remote view inside the app's window, so its controls are in `app`'s tree (`UIA.Health.Allow.Button`). Both are polled until the lookup timeout, because a sheet arrives a beat after the launch that asks for it. Only an *enabled*, *hittable* control is taken — HealthKit's `Allow` is present and disabled until a topic is chosen, and tapping it would land nothing.
    ///
    /// **In the app's tree, only what `scope` admits** (the SimWalk#28 review): a control in a subtree the app's own screen did not have before the sheet could be up (`SystemSheetBaseline`). The app's own `Continue`, on a device that has already answered, is the app's and never tapped — the step is UNREACHABLE naming the label, and says the app's own control was there, or that the step is ambiguous where that screen already held one (`SystemSheetScope.refusal`). SpringBoard draws nothing of the app's, so a control there needs no such check. The step is recorded with the tree its control came from, and with whether its sheet closed: once the control has gone, the app's tree read until nothing the sheet brought is still there, or `dismissalWait` has passed (`SystemSheetScope.closing`).
    ///
    /// **A control below the fold is not in the tree as itself**, so waiting for it to become reachable never ends: measured on HealthKit's sheet, its buttons are reported as bare text with a made-up frame until their cell is scrolled on screen, and only then as `Button`s with their identifiers. So a scroll container the sheet brought — never the app's own list, which a drag before a slow sheet arrives would move — is dragged towards its end once it has been up for `scrollAfter` without the control, a bounded number of drags; a later sheet's container is scrolled too, each once per step. SpringBoard's alerts do not scroll, so only the app's tree is moved.
    ///
    /// Landed is the touch delivered: `Select All` changes the sheet without dismissing it.
    private func systemTap(_ label: String, atLaunch: Bool, over app: XCUIApplication, reading sheetReads: WalkRunner.SheetReads, admitting scope: SystemSheetScope) throws -> StepResult {
        let springboard = XCUIApplication(bundleIdentifier: Self.springboardBundleID)
        var deadline = Date().addingTimeInterval(Self.timeout)
        var containerFirstSeen: [String: Date] = [:]
        var scrolled: Set<String> = []
        var search = SystemTapSearch(label: label, scope: scope)
        repeat {
            if let control = Self.firstTappable(label, in: springboard) {
                let gone = try Self.tapSystemControl(
                    control,
                    reading: { try AXTreeCapture.tree(of: springboard) },
                    stillHolds: { SystemSheetScope.holds(control.node, in: $0) }
                )
                return .landedAs(.systemTap(label: label, atLaunch: atLaunch, owner: .springboard), sheetClosed: gone)
            }
            let springBoardShowedSheet = Self.liveRead(or: false) { springboard.alerts.firstMatch.exists }
            let current = try sheetReads.appTree()
            if let admitted = search.poll(current, springBoardShowedSheet: springBoardShowedSheet, find: { Self.firstTappable(label, in: app, where: $0) }) {
                let gone = try Self.tapSystemControl(admitted, reading: sheetReads.appTree) { scope.stillHolds(admitted.node, in: $0) }
                let closed = try gone && Self.sheetClosed(in: current, holding: admitted.node, reading: sheetReads, admittedBy: scope)
                return .landedAs(.systemTap(label: label, atLaunch: atLaunch, owner: .appWindow), sheetClosed: closed)
            }
            if let target = scope.scrollContainer(in: current), !scrolled.contains(target.path) {
                let seen = containerFirstSeen[target.path] ?? Date()
                containerFirstSeen[target.path] = seen
                if Date().timeIntervalSince(seen) >= Self.scrollAfter {
                    scrolled.insert(target.path)
                    // The drags' own time is not the lookup's: they are bounded by `scrollAttempts`, and a
                    // control the last drag brought on screen still needs the poll that admits it. Eight
                    // drags down HealthKit's 59-type sheet spent the whole budget, and the step was refused
                    // with `Allow` enabled and hittable on screen (2026-09-23).
                    let dragging = Date()
                    Self.scrollToEnd(of: target.node, in: app, until: label)
                    deadline.addTimeInterval(Date().timeIntervalSince(dragging))
                    continue
                }
            }
            Thread.sleep(forTimeInterval: Self.settleInterval)
        } while Date() < deadline
        let refusal = search.refusal(bootAge: WalkRunner.deviceBootAge)
        return .blocked(reason: refusal.reason, cause: refusal.cause)
    }

    /// Whether the sheet `before` held `tapped` in has closed, now that the control has gone: the app's tree read until `SystemSheetScope.closing` answers, within `dismissalWait`, since a sheet's container animates out after its control (the #39 review's finding 3).
    private static func sheetClosed(in before: AXNode, holding tapped: AXNode, reading sheetReads: WalkRunner.SheetReads, admittedBy scope: SystemSheetScope) throws -> Bool {
        let started = Date()
        while true {
            let after = try sheetReads.appTree()
            switch scope.closing(sheetIn: before, holding: tapped, by: after, elapsed: Date().timeIntervalSince(started), within: dismissalWait) {
            case .closed:
                return true
            case .stillUp:
                return false
            case .readAgain:
                Thread.sleep(forTimeInterval: settleInterval)
            }
        }
    }

    /// Taps `control` and answers whether it went away: the owner's tree, as `read` reads it, read until `stillHolds` no longer answers true of it, or `dismissalWait` has passed.
    ///
    /// **Judged from the tree, never the element** (SimWalk#47). The tap is a coordinate, so nothing here is bound by index: the element's own `waitForNonExistence` would look it up again at every poll, and index N of a set that changed under a decelerating table is a different control, or none. A snapshot read throws where a query fails. The app's tree is read through `SheetReads`, as the poll that admitted the control read it, so a remote sheet's control is not taken for gone because the snapshot never held it (SimWalk#48). The caller says what still holding it means: in SpringBoard, `SystemSheetScope.holds`, by type, label and identifier anywhere; in the app's window, `SystemSheetScope.stillHolds`, which is `admits` and so tells the sheet's control from an identical one the app keeps (the #47 review). A control whose label the tap changed reads as gone either way, and whether its sheet closed is left to `sheetClosed`.
    private static func tapSystemControl(_ control: SystemControl, reading read: () throws -> AXNode, stillHolds: (AXNode) -> Bool) throws -> Bool {
        control.point.tap()
        // A control that dismisses its sheet is let go first: HealthKit's `Allow` is labelled as the
        // notifications alert's is, and while it animates out a next `systemTap 'Allow'` would find it
        // again in the app's window before SpringBoard's alert is up.
        let tapped = Date()
        while true {
            if try !stillHolds(read()) {
                return true
            }
            guard Date().timeIntervalSince(tapped) < dismissalWait else { return false }
            Thread.sleep(forTimeInterval: settleInterval)
        }
    }

    /// The first control matching `label` in `owner`'s tree that a tap would land on — enabled and hittable — and that `accepts` takes, `Button`s before any other kind, since a button's own text carries its label too.
    ///
    /// **Read from snapshots, never property by property** (SimWalk#47). An element bound by index is found again on every read, and while a sheet's table decelerates HealthKit's rows turn from bare text into `Button`s, so the matching set changes between one read and the next and XCUITest records "No matches found for Element at index N" as a test failure — the walk ends with no step outcome. `snapshot()` throws instead, and an element whose snapshot cannot be taken is passed over, as one that has gone.
    ///
    /// **Each candidate in turn, read twice around its live reads** (SimWalk#51, item 1): the sequence is `SystemControlReread.firstTappable`'s, where a test replays it (SimWalk#55), and this supplies the reads. Hittability and the live frame have no snapshot form, so they are read live straight after an `exists`, which answers false rather than failing, and through `liveRead`, so a read that fails after it passes the candidate over too (SimWalk#60); the element's snapshot is taken again after them, and a control whose second read is not the same one is passed over.
    ///
    /// **The first acceptable one, and tapped by its point** (the #47 review). The walk stops at the first element that passes, so the gap after its second snapshot is the caller's tap and nothing more; and the tap is a coordinate at its box's centre, taken from `owner` — the process it was found in — which never looks the element up again. Tapped by index, a matching set that changed in that gap would record "No matches found", or land on a match `accepts` never took.
    ///
    /// **The live frame places the tap; the snapshot's is the node's.** An element's own `snapshot()` reports a remote sheet's content in the sheet's coordinates, as `app.snapshot()` does — measured on HealthKit's, iOS 27.0: `UIA.Health.AuthSheet.AllCategoryButton` live at y 407.05, y 341 in its own snapshot and in the tree — so a tap at the snapshot's box lands 66 points above the control. So the two snapshots are compared with each other, never with the live frame; the node keeps the snapshot's, the space `accepts` compares against the tree in.
    private static func firstTappable(_ label: String, in owner: XCUIApplication, where accepts: (AXNode) -> Bool = { _ in true }) -> SystemControl? {
        let matches = owner.descendants(matching: .any).matching(TargetResolution.labelPredicate(label)).allElementsBoundByIndex
        let found = SystemControlReread.firstTappable(
            among: matches,
            snapshot: { element in (try? element.snapshot()).map { AXTreeCapture.node(of: $0) } },
            live: { element -> CGRect? in
                guard element.exists else { return nil }
                return liveRead(or: nil) {
                    let frame = element.frame
                    return element.isHittable ? frame : nil
                }
            },
            where: accepts
        )
        guard let found else { return nil }
        let bounds = owner.frame
        let point = owner.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: found.live.midX - bounds.origin.x, dy: found.live.midY - bounds.origin.y))
        return SystemControl(node: found.node, point: point)
    }

    /// Drags the scroll container `container` names towards its end, up to `scrollAttempts` times, stopping as soon as a match for `label` reads enabled and hittable, whether or not it has stopped moving.
    ///
    /// **The drags bring the control on screen; the step's poll admits and taps it** (SimWalk#59). `SystemTapScroll.keepsDragging` decides from one read of each match, where `firstTappable` reads twice and refuses a box that moved: on HealthKit's sheet `Allow` was in reach from the first drag, but the list was still bouncing, so each check between drags refused it, the next drag kept it bouncing, and all twelve were spent (about 18 s). The step's poll waits `settleInterval` between reads and holds the control to every check, so nothing is tapped here.
    ///
    /// By app coordinates from the box the tree read gave, never through a live element (SimWalk#45). Binding the containers by index and reading each one's frame back is a query per read, and on HealthKit's 59-type sheet the matching set changed between the bind and the read — XCUITest raises that as a test failure ("No matches found for Element at index 1"), which ended the walk with no step outcome at all. A drag between two points, because a `swipeUp()` on the container a `containing` query found hung the runner on the same sheet (2026-09-22). The box is in the sheet's own coordinate space where the sheet is remote (its table reads y 0 in the snapshot and sits at y 62 live, iOS 27.0), so the two points are taken well inside it, at 0.2 and 0.8 of its height, where that offset still lands both on the container.
    private static func scrollToEnd(of container: AXNode, in app: XCUIApplication, until label: String) {
        let bounds = app.frame
        let box = container.frame
        // A box shorter than this puts the two points nearly together, and each "drag" becomes a press and
        // release — a tap on whatever sits there, up to `scrollAttempts` times (the #45 review).
        guard box.height >= 40 else { return }
        let x = box.x + box.width / 2 - bounds.origin.x
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let lower = origin.withOffset(CGVector(dx: x, dy: box.y + box.height * 0.8 - bounds.origin.y))
        let upper = origin.withOffset(CGVector(dx: x, dy: box.y + box.height * 0.2 - bounds.origin.y))
        for _ in 0 ..< scrollAttempts {
            guard keepsDragging(label, in: app) else { return }
            lower.press(forDuration: scrollPress, thenDragTo: upper)
        }
    }

    /// Waits until the hierarchy has left the screen a navigating step was taken on, and answers whether it did.
    ///
    /// A wait rather than a check, which is the half that makes the guard cost nothing on a healthy app: a push registers in the hierarchy within an interval or two, so the usual answer is yes almost immediately and the settle window then opens on the screen that was actually reached. The budget only matters when the answer is no — and a step that never moved the screen is a step that did not land, which is an UNREACHABLE naming it rather than a capture of the screen it failed to leave.
    private func arrived(leaving departed: ScreenIdentity, in app: XCUIApplication, budget: TimeInterval) throws -> Bool {
        let acted = Date()
        let deadline = acted.addingTimeInterval(budget)
        repeat {
            if try departed.hasBeenLeft(by: AXTreeCapture.tree(of: app)) {
                arrival.landedAfter = Date().timeIntervalSince(acted)
                return true
            }
            Thread.sleep(forTimeInterval: Self.settleInterval)
        } while Date() < deadline
        let left = try departed.hasBeenLeft(by: AXTreeCapture.tree(of: app))
        if left {
            arrival.landedAfter = Date().timeIntervalSince(acted)
        }
        return left
    }

    /// The value of the text-entry element holding keyboard focus: `.none` when none does (or it carries no string value), `.unreadable` when a live read of a candidate failed and no other held a value (SimWalk#96).
    ///
    /// Only text-entry types are asked, so the field is what is read and not a focused container around it. Every read is a `liveRead`: a Done or Return that dismisses the keyboard takes the field out between `exists` and `value`, and a read that records an issue there would fail the whole walk (SimWalk#60, #94).
    private static func focusedFieldValue(in app: XCUIApplication) -> FocusedFieldValue {
        let queries = [app.textFields, app.secureTextFields, app.textViews, app.searchFields]
        let focus = NSPredicate(format: "hasKeyboardFocus == true")
        var unreadable = false
        for query in queries {
            let focused = query.matching(focus).firstMatch
            let value = liveRead(or: FocusedFieldValue.unreadable) {
                (focused.exists ? focused.value as? String : nil).map(FocusedFieldValue.value) ?? .none
            }
            if value == .unreadable {
                unreadable = true
            } else if value != .none {
                return value
            }
        }
        return unreadable ? .unreadable : .none
    }

    /// Waits until a tapped keyboard key has landed — the screen left, or the focused field's value no longer what it was — and answers whether it did.
    ///
    /// `arrived`'s clock with the key's second witness read in the same pass (`TypedTextLanding.keyPressed`), so a keystroke that lands is answered on the first read rather than after the whole budget.
    private func keyLanded(leaving departed: ScreenIdentity, focusedBefore: FocusedFieldValue, in app: XCUIApplication, budget: TimeInterval) throws -> Bool {
        func landed() throws -> Bool {
            let screenLeft = try departed.hasBeenLeft(by: AXTreeCapture.tree(of: app))
            return TypedTextLanding.keyLanded(screenLeft: screenLeft, before: focusedBefore, after: Self.focusedFieldValue(in: app))
        }
        let deadline = Date().addingTimeInterval(budget)
        repeat {
            if try landed() {
                return true
            }
            Thread.sleep(forTimeInterval: Self.settleInterval)
        } while Date() < deadline
        return try landed()
    }

    /// Waits until an `openURL` step has arrived — the app still in front and its hierarchy off the screen the step was taken on — and answers whether it did, naming why not where the app was left behind another.
    ///
    /// `OpenURLLanding` decides; this keeps the clock and the reads. The tree is read only while the app is in front, because a URL that opened another app changes the walked app's tree by sending it to the background, and that is not arrival.
    private func openedURLArrived(leaving departed: ScreenIdentity, in app: XCUIApplication, budget: TimeInterval) throws -> StepResult {
        let acted = Date()
        let deadline = acted.addingTimeInterval(budget)
        while true {
            let pastDeadline = Date() >= deadline
            let inFront = app.state == .runningForeground
            let left = try inFront && departed.hasBeenLeft(by: AXTreeCapture.tree(of: app))
            switch OpenURLLanding.next(appInFront: inFront, leftScreen: left, pastDeadline: pastDeadline) {
            case .watch:
                Thread.sleep(forTimeInterval: Self.settleInterval)
            case .landed:
                arrival.landedAfter = Date().timeIntervalSince(acted)
                return .landed
            case let .notLanded(reason):
                return .blocked(reason: reason)
            }
        }
    }

    /// How long a tapped system control is given to go away; one that stays — `Select All` — costs this once.
    private static var dismissalWait: TimeInterval {
        2
    }

    /// Whether `scrollToEnd` drags again: `SystemTapScroll.keepsDragging` over one read of each live match for `label` in `app` — its snapshot, then whether a tap would land on it (SimWalk#59).
    ///
    /// Read through snapshots, `exists` and `liveRead` as `firstTappable` reads, so a match that goes mid-read, or sits under the sheet's header, is passed over rather than recorded as a test failure (SimWalk#47, #60).
    private static func keepsDragging(_ label: String, in app: XCUIApplication) -> Bool {
        SystemTapScroll.keepsDragging(
            over: app.descendants(matching: .any).matching(TargetResolution.labelPredicate(label)).allElementsBoundByIndex,
            snapshot: { element in (try? element.snapshot()).map { AXTreeCapture.node(of: $0) } },
            hittable: { element in element.exists && liveRead(or: false) { element.isHittable } }
        )
    }

    /// How long a sheet's scroll container is up without `systemTap`'s control before it is dragged: a sheet's content arrives a beat after the sheet, and a list dragged before then scrolls a control at its top out of reach.
    private static var scrollAfter: TimeInterval {
        2
    }

    /// How long a scrolling drag holds before it moves — short enough to scroll rather than select.
    static var scrollPress: TimeInterval {
        0.05
    }

    static var springboardBundleID: String {
        "com.apple.springboard"
    }

    static var timeout: TimeInterval {
        10
    }

    /// How long a tapped row the snapshot read as selected is given to become hittable before `TapLanding` judges it covered; short, because a covered row pays it in full and a hittable one pays nothing.
    private static var selectedHittableWait: TimeInterval {
        2
    }

    /// How many swipes a `scrollTo` gets before it gives up and reports the screen unreachable — looking for its label and then bringing what it found within reach, together (`ScrollSearch`).
    ///
    /// Bounded rather than open-ended: a label that exists in the hierarchy but can never be brought on screen would otherwise swipe forever, and "I could not reach it" is a perfectly good answer for a walk to give.
    private static var scrollAttempts: Int {
        12
    }

    /// How long to leave between those reads — long enough for a push or a fade to advance visibly, short enough that a settled screen costs one interval.
    ///
    /// From `SettleWindow`, which is also what rounds the recorded quiet period to a multiple of it: the loop's step and the manifest's claim are the same number, and two spellings of it would let the bundle state a window the loop never waited.
    static var settleInterval: TimeInterval {
        SettleWindow.interval
    }
}

extension StepPerformer {
    /// What `read` answers, or `fallback` where XCUITest recorded an issue during it — a live read of a system sheet's element that failed answers as the element having gone (SimWalk#60).
    ///
    /// **A failed read is an answer, never a test failure.** `exists` answers false rather than failing, but the reads after it do not: an element can go between `exists` and its frame, and `isHittable` on a HealthKit cell a drag left under the sheet's header records "Activation point invalid" (iOS 27.0, 2026-09-24) — the walk failed with the candidate unanswered. So the read runs as a non-strict expected failure, as the graft's count does (SimWalk#48): an issue there is marked expected rather than recorded against the walk, none is no issue at all, and any issue makes the answer `fallback`, since the value XCUITest hands back after recording one says nothing about the element.
    static func liveRead<Value>(or fallback: Value, _ read: () -> Value) -> Value {
        var failed = false
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        options.issueMatcher = { _ in
            failed = true
            return true
        }
        let value = XCTExpectFailure("a system sheet's element can fail a live read: gone, or under the sheet's header (SimWalk#60)", options: options) {
            read()
        }
        return failed ? fallback : value
    }
}

extension StepPerformer {
    /// Whether a route step landed, and when it did not, why — where the runner can say.
    enum StepResult {
        case landed
        /// Landed, having bound this element — a `tap`, `scrollTo` or `type` — as the snapshot read it (SimWalk#93).
        case landedOn(AXNode)
        /// Landed, and recorded in `routeTaken` as this step — what the runner learned doing it, a `systemTap`'s owner — and whether the sheet it answered closed, which is when `SystemSheetBaseline` reads the app's screen again.
        case landedAs(Walkbook.RouteStep, sheetClosed: Bool)
        /// The step did not land; `reason` is what the UNREACHABLE says beyond the route, `nil` where there is nothing more to say, and `cause` names it where the walk's verdict counts it on its own.
        case blocked(reason: String?, cause: ScreenOutcome.UnreachableCause? = nil)

        init(_ landed: Bool) {
            self = landed ? .landed : .blocked(reason: nil)
        }
    }

    /// What binding a route step's choice to a live element came to (`bind`).
    enum Binding {
        /// The live element, the candidate it is, and the choice that found it.
        case element(XCUIElement, RouteTarget.Candidate, RouteTarget.Choice)
        /// The element chosen could not be bound, and nothing else was found to be the same element.
        case moved(RouteTarget.Candidate)
        /// Nothing to act on, and why — where the runner can say.
        case refused(String?)

        /// Why a step that meant to have `verb` its element acts on nothing, or `nil` when it acts.
        func refusal(doing verb: String) -> String? {
            switch self {
            case .element: nil
            case let .moved(target): "\(target.description) moved before it could be \(verb)"
            case let .refused(reason): reason
            }
        }
    }

    /// Whether `element`, read again, is still the one `target` chose (`RouteTarget.Candidate.isStill`) — `false` once it is gone.
    static func isStill(_ element: XCUIElement, as target: RouteTarget.Candidate) -> Bool {
        guard element.exists else { return false }
        let live = element.frame
        let frame = AXNode.Frame(x: Double(live.origin.x), y: Double(live.origin.y), width: Double(live.size.width), height: Double(live.size.height))
        return target.isStill(label: element.label, identifier: element.identifier, frame: frame)
    }

    /// A control a `systemTap` takes: the node its snapshot read, and the point a tap on it lands on.
    struct SystemControl {
        let node: AXNode
        let point: XCUICoordinate
    }
}

extension StepPerformer {
    /// How long a navigating step took from its action returning to the read that showed it had arrived (SimWalk#67, M2): a class, so the non-mutating `perform` can leave it for the route loop to read.
    @MainActor
    final class Arrival {
        var landedAfter: TimeInterval?
    }
}
