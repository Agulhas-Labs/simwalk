//
// Copyright © Agulhas Labs
//

import Foundation

/// One state's two artefacts, read once the app's tree held still and cleared of any system alert over the app (SimWalk#4, #28, #39 item 5).
///
/// **Only `take` makes one** (`init` is private), and the runner files nothing else, so the refusal under a system alert is in the one sequence that can produce a capture at all. Before, the runner called the check itself, and deleting that call left `swift test` green: the refusal was pinned by one live run (SimWalk#39 item 5). Here a test replays the sequence against a scripted `CaptureSource` and fails when the check is gone.
///
/// **The picture is taken between two reads, and kept only if they agree** — `SettleTracker` decides when — and **SpringBoard is read after the picture**, so an alert in it is still up when this looks: alerts do not dismiss themselves. `app.snapshot()` returns the app's own tree under one, a tree of a screen the picture does not show, so neither is filed and the capture is refused naming the alert.
public struct SettledCapture {
    /// The screen's picture.
    public let screenshot: Data
    /// The app's tree, of the same moment as the picture where `didSettle`.
    public let tree: AXNode
    /// Whether the tree held still with more than the app's chrome in it and bracketed the picture; `false` for a screen still moving when the budget ran out, or still bare when the content wait did (SimWalk#81), captured and flagged.
    public let didSettle: Bool
    /// How long after the source began watching the kept picture was taken, by the source's own `elapsed()` — the moment the figures in it were on screen.
    ///
    /// What a capture's `capturedAt` is made from, so a rolling window is computed back from the read rather than from when the artefacts were filed: the runner holds every state of a screen until the last is read, and a state read at 23:59:40 would otherwise be stamped after midnight by the relaunches its siblings cost.
    public let takenAfter: TimeInterval
    /// What the watch saw of the screen settling and moving — its settle time where it settled, its cadence and reads, and the layout shifts between them — where the walk asks for `motion` (SimWalk#67); `nil` where it does not, the record "motion not recorded" files.
    public let motion: CaptureManifest.Motion?

    private init(screenshot: Data, tree: AXNode, didSettle: Bool, takenAfter: TimeInterval, motion: CaptureManifest.Motion?) {
        self.screenshot = screenshot
        self.tree = tree
        self.didSettle = didSettle
        self.takenAfter = takenAfter
        self.motion = motion
    }

    /// Reads a capture from `source`: watched until the tree holds still for `quiet` with more than the app's chrome in it, or `budget` is spent — on a tree that stays bare, `SettleWindow.contentWait` where that is longer — then cleared against SpringBoard's tree.
    ///
    /// **Each read the watch compares is folded only when `motion` is given**, for `LayoutShiftRule` to find what moved between them: only the previous tree is held, not the watch's tens of them (SimWalk#96), and only by a walk that asked for the record. **`motion` has no default**, so the runner has to state whether it records motion and what its route did; that pins the argument, not the honesty of what it passes.
    ///
    /// - Parameter motion: What the route told the watch, where the walk records motion; `nil` folds no reads and makes no record.
    /// - Throws: `Refusal` when a system alert covers the app, or SpringBoard's tree cannot be read to say; whatever `source` throws reading the app.
    public static func take(from source: some CaptureSource, quiet: TimeInterval, budget: TimeInterval, interval: TimeInterval, motion: MotionWatch?) throws -> Self {
        var tracker = SettleTracker(quiet: quiet, budget: budget, interval: interval, contentWait: SettleWindow.contentWait)
        var tree = try source.appTree()
        var screenshot = Data()
        var takenAfter: TimeInterval = 0
        var fold = LayoutShiftRule.Fold(afterScroll: motion?.afterScroll ?? false)
        func record() -> CaptureManifest.Motion? {
            motion.map { CaptureManifest.Motion(of: tracker, interval: interval, fold: fold, watch: $0) }
        }
        while true {
            let elapsed = source.elapsed()
            if motion != nil {
                fold.add(LayoutShiftRule.Read(elapsed: elapsed, tree: tree))
            }
            switch tracker.next(tree: tree, elapsed: elapsed) {
            case .watch:
                source.pause(interval)
                tree = try source.appTree()
            case .takeScreenshot:
                takenAfter = source.elapsed()
                screenshot = source.screenshot()
                // Read immediately and without waiting: this read *is* the bracket, and a pause inside it
                // is the very window the bracket exists to close.
                tree = try source.appTree()
            case .settled:
                try clear(source)
                return Self(screenshot: screenshot, tree: tree, didSettle: true, takenAfter: takenAfter, motion: record())
            case .unsettled:
                // Still captured, and flagged. A screen that never settles — a spinner, a looping
                // animation — is genuinely a moving screen, and refusing would make an animated app
                // unwalkable; what was never acceptable is capturing one silently. The two artefacts are
                // taken as close together as they can be and claim nothing more than that.
                let movingAfter = source.elapsed()
                let moving = source.screenshot()
                let movingTree = try source.appTree()
                try clear(source)
                return Self(screenshot: moving, tree: movingTree, didSettle: false, takenAfter: movingAfter, motion: record())
            }
        }
    }

    /// Throws `Refusal` when SpringBoard draws an alert over the app, or its tree cannot be read to say.
    private static func clear(_ source: some CaptureSource) throws {
        let springboard: AXNode
        do {
            springboard = try source.springboardTree()
        } catch {
            throw Refusal(description: "reading SpringBoard's tree: \(error)")
        }
        if let alert = SystemAlertCheck.coveringAlert(in: springboard) {
            throw Refusal(description: alert)
        }
    }
}

public extension SettledCapture {
    /// A capture refused because a system alert covered the app, or because SpringBoard's tree could not be read to say; its description is what the manifest's `captureFailed` says.
    struct Refusal: Error, CustomStringConvertible, Equatable {
        public let description: String
    }
}
