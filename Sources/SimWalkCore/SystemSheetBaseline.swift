//
// Copyright © Agulhas Labs
//

import Foundation

/// When the app's screen is read as a `systemTap`'s baseline, step by step along a route (SimWalk#39).
///
/// **Read before each step that is not a `systemTap`, so whatever that step raises is new.** A `tap 'Connect Health'` whose only effect is HealthKit's sheet lands once the screen has changed, and that change *is* the sheet: read after the tap, the sheet's `Allow` — there from the start, disabled until a topic is chosen — would read as the app's own and the step be refused (the #39 review's finding 1). The price is the known limit: a step that pushes the app's own page with a control the `systemTap` names — an identified `Allow` of its own — has that control read as new, and admitted as `appWindow`.
///
/// **Read at once when the route begins with a `systemTap`.** The launch is then the step that raised the sheet, and the read cannot come before it; a sheet already up by then reads as the app's own, and `SystemSheetScope.refusal` names the step ambiguous rather than tapping either, and names the `atLaunch` declaration that would take it (SimWalk#39 item 2). **Unless the step is declared `atLaunch`** (SimWalk#46): the author's word that the launch raised the sheet, so the scope admits every subtree of the launch's screen (`SystemSheetScope.admittingAll(of:)`) and is kept like any other — but for a sheet hosted in the app's window it is never dropped: its only baseline path is the root, so `SystemSheetScope.closing` judges the whole window and never reads the sheet as closed; the step that closes it waits out the dismissal wait, and a later `systemTap` in the route answers from the same accept-everything scope.
///
/// **Kept while the sheet it was read for is up; read again once that sheet closes.** `Select All` and HealthKit's `Continue` leave the sheet up, and its next control is new only against the screen from before it. Once the sheet has closed (`SystemSheetScope.closing`) the app may put up controls of its own — a notifications primer with its own `Allow` — so the next `systemTap` reads the screen again rather than admitting them, and that first read waits for the screen to settle, since the primer comes a moment after the sheet has gone.
///
/// **A route with no `systemTap` still to come reads nothing**, when the baseline is made knowing its route. A value the runner asks before each step and tells after one lands, like `SettleTracker`, so a test replays the route without a simulator.
public struct SystemSheetBaseline: Sendable {
    /// The scope in hand, or `nil` when the next `systemTap` reads the screen.
    private var scope: SystemSheetScope?
    /// How many of the route's `systemTap`s are still to be asked for, or `nil` when the route is not known and one may follow any step.
    private var systemTapsAhead: Int?
    /// Whether any step has landed, so a `systemTap` reading the screen now is not reading the launch's.
    private var anyLanded = false
    /// Whether a sheet closed since the screen was last read, so the next read waits for it to settle.
    private var settleNextRead = false
    /// The route and each step's quiet period, when the baseline was made for a walkbook's screen (`scope(forStep:from:)`).
    private var steps: [(step: Walkbook.RouteStep, quiet: TimeInterval)] = []
    /// The quiet period `scope(forStep:from:)` falls back to for an index `steps` has no entry for — a baseline made without a route, or an index past the one it was made for (SimWalk#56).
    private var defaultQuiet: TimeInterval = 0

    /// A baseline for a route it is not told, so every step that is not a `systemTap` reads the screen, in case one follows.
    public init() {}

    /// A baseline for `route`, which reads nothing once no `systemTap` is still to come.
    public init(route: [Walkbook.RouteStep]) {
        systemTapsAhead = route.count(where: \.isSystemTap)
    }

    /// A baseline for `screen`'s route in `walkbook`, which knows the quiet period each step is taken under: that of the screen the step is taken on, else `defaultQuiet` (`SettleWindow.quiet(forStep:of:in:default:)`).
    public init(screen: Walkbook.Screen, of walkbook: Walkbook, defaultQuiet: TimeInterval) {
        self.init(route: screen.route)
        self.defaultQuiet = defaultQuiet
        steps = screen.route.indices.map { (screen.route[$0], SettleWindow.quiet(forStep: $0, of: screen, in: walkbook, default: defaultQuiet)) }
    }

    /// The scope the route's step at `index` answers from, as `scope(for:from:quiet:)` gives it, under the quiet period of the screen the step is taken on — or, for an `index` `steps` has no entry for (a baseline made without a route, or an index past the one it was made for), the plain read `scope(for:from:quiet:)` gives a step that is not a `systemTap`, under `defaultQuiet`.
    ///
    /// **The quiet period is found here, not passed in** (SimWalk#55): a runner that passed the walk's own, or none, would read the screen the moment a sheet closed and admit the primer the app puts up after it — and nothing `swift test` compiles would notice.
    public mutating func scope(forStep index: Int, from screen: some TreeSource) throws -> SystemSheetScope? {
        guard steps.indices.contains(index) else {
            if systemTapsAhead.map({ $0 > 0 }) ?? true {
                scope = try SystemSheetScope(baseline: read(screen, quiet: defaultQuiet))
            }
            return nil
        }
        return try scope(for: steps[index].step, from: screen, quiet: steps[index].quiet)
    }

    /// The scope `step` answers from, or `nil` for a step that is not a `systemTap` — which reads `screen` before it while a `systemTap` is still to come.
    ///
    /// A `systemTap` answers from the scope in hand, else one read now: the launch's screen, or the screen once the sheet before it closed. **The first read after a sheet closed waits for the screen to hold still for `quiet`** — the quiet period of the screen the step is taken on — so a primer the app puts up a moment after the dismissal is in the baseline and not admitted; every other read is a single one.
    mutating func scope(for step: Walkbook.RouteStep, from screen: some TreeSource, quiet: TimeInterval) throws -> SystemSheetScope? {
        guard step.isSystemTap else {
            if systemTapsAhead.map({ $0 > 0 }) ?? true {
                scope = try SystemSheetScope(baseline: read(screen, quiet: quiet))
            }
            return nil
        }
        systemTapsAhead = systemTapsAhead.map { $0 - 1 }
        if let scope {
            return scope
        }
        let read = if step.isDeclaredAtLaunch {
            try SystemSheetScope.admittingAll(of: read(screen, quiet: quiet))
        } else if anyLanded {
            try SystemSheetScope(baseline: read(screen, quiet: quiet))
        } else {
            try SystemSheetScope.readAtLaunch(of: read(screen, quiet: quiet))
        }
        scope = read
        return read
    }

    /// Records that `step` landed, and whether the sheet a `systemTap` answered closed with it: a sheet that closed leaves the app free to show controls of its own, so the next read of the screen waits for it to settle.
    public mutating func landed(_ step: Walkbook.RouteStep, sheetClosed: Bool) {
        anyLanded = true
        if step.isSystemTap, sheetClosed {
            scope = nil
            settleNextRead = true
        }
    }

    /// The app's tree for a baseline: once it has held still for `quiet` where a sheet closed since the last read, else as it is now.
    ///
    /// **Settled only after a sheet closed** (SimWalk#39 item 1, scenario B). HealthKit's `Allow` dismisses its sheet and the app's completion handler then puts up a notifications primer with an `Allow` of its own; read the moment the sheet's subtree is gone, the primer is not there yet, and the next `systemTap 'Allow'` admits it as the sheet's. Waiting for stillness puts it in the baseline — as long as it arrives within the quiet period of the sheet's going; an app slower than that still gets through. Every other read stays a single one: a sheet the step before raised has to arrive *after* the read to be new, and waiting there would fold it into the baseline.
    private mutating func read(_ screen: some TreeSource, quiet: TimeInterval) throws -> AXNode {
        guard settleNextRead else { return try screen.appTree() }
        settleNextRead = false
        var tracker = SettleTracker(quiet: quiet, budget: SettleWindow.budget(forQuiet: quiet))
        let started = screen.elapsed()
        var tree = try screen.appTree()
        while true {
            switch tracker.next(tree: tree, elapsed: screen.elapsed() - started) {
            case .watch:
                screen.pause(SettleWindow.interval)
                tree = try screen.appTree()
            case .takeScreenshot, .settled, .unsettled:
                // Held still for `quiet`, or the budget is spent on a screen still moving: either way this is
                // the screen to read. No picture is taken, so the bracketing read a capture needs is not.
                return tree
            }
        }
    }
}

extension Walkbook.RouteStep {
    /// Whether this step answers a system sheet, which is what decides when the app's screen is read as its baseline.
    var isSystemTap: Bool {
        if case .systemTap = self {
            return true
        }
        return false
    }

    /// Whether this step is a `systemTap` the walkbook declares the launch raised the sheet for.
    var isDeclaredAtLaunch: Bool {
        if case .systemTap(_, true, _) = self {
            return true
        }
        return false
    }
}
