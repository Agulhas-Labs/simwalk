//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// One mirror call's whole sequence, in one place, over injected seams (Brief §8 "The observation").
///
/// **The order is the contract, and the seams let a test replay it.** The call lock is held throughout, and the store's scratch is emptied first, under it, so a call killed mid-read leaves nothing behind past the next call. The guard comes first, because activating Mirroring can bring its window on screen, so the window is looked up only after it, and an action's points are checked against the window's shape before anything is captured. An action is preceded by a before-read and followed by reads every ``MirrorSettle/intervalMilliseconds`` until ``MirrorSettle`` decides; a plain `read` has no before-read. Only the served read's capture is kept; every other one is deleted, on success and on a thrown error alike.
///
/// **The event is posted on a recheck taken just before it, never on the guard's clearance.** The before-read sits between the two — a capture and 60–300 ms of OCR, 25–110 s on a binary's first read — and focus can move in that time, so one more read of the frontmost process (``MirrorFocusRefusal/Moment/beforeAction``) comes immediately before the event, and the event goes out on its clearance.
///
/// A burst posts one tap, on the same recheck, then captures frames as fast as capture goes, re-checking focus before each, and reads them all only after the last capture, so Vision's time is never spent between frames.
public struct MirrorStepRunner {
    private let seams: Seams
    private let store: MirrorCaptureStore
    private let lock: MirrorCallLock

    /// The live runner: the real guard, window lookup, poster, menu, capture, Vision, clock and sleep.
    public init(store: MirrorCaptureStore = .standard(), lock: MirrorCallLock = .standard()) {
        let focus = MirrorFocusGuard()
        let capture = MirrorCapture()
        let reader = VisionTextReader()
        self.init(
            seams: Seams(
                clear: { try focus.clear() },
                recheck: { try focus.recheck(at: $0) },
                window: { try MirrorWindow.current() },
                perform: { action, window, clearance in try Self.post(action, in: window, focus: focus, clearance: clearance) },
                capture: { window, file, clearance in try capture.capture(window: window, to: file, clearance: clearance) },
                read: { url, date in try reader.read(url, capturedAt: date) },
                now: Date.init,
                pause: Thread.sleep(forTimeInterval:)
            ),
            store: store,
            lock: lock
        )
    }

    init(seams: Seams, store: MirrorCaptureStore, lock: MirrorCallLock) {
        self.seams = seams
        self.store = store
        self.lock = lock
    }

    /// Runs `action`, or a plain `read` for `nil`, and answers what the screen settled on.
    ///
    /// The before-read's capture is deleted with the intermediate ones, so its `path` in the result names nothing on disk.
    ///
    /// - Parameters:
    ///   - settleMilliseconds: How long to keep reading before answering with what is there.
    public func run(_ action: MirrorAction?, settleMilliseconds: Int = 3000) throws -> MirrorObservation {
        try lock.withLock {
            store.clearScratch()
            let clearance = try seams.clear()
            let window = try seams.window()
            if let action {
                try Self.refuseOffScreen(action, in: window)
            }
            var scratch: [URL] = []
            defer { scratch.forEach { try? FileManager.default.removeItem(at: $0) } }
            func capturedRead(_ clearance: MirrorFocus.Clearance) throws -> MirrorRead {
                let file = try store.scratchFile()
                scratch.append(file)
                try seams.capture(window, file, clearance)
                return try seams.read(file, seams.now())
            }
            var before: MirrorRead?
            var afterClearance = clearance
            if let action {
                before = try capturedRead(clearance)
                afterClearance = try seams.perform(action, window, seams.recheck(.beforeAction))
            }
            let eventAt = seams.now()
            var settle = MirrorSettle(before: before, boundMilliseconds: settleMilliseconds)
            while true {
                seams.pause(TimeInterval(MirrorSettle.intervalMilliseconds) / 1000)
                let current = try capturedRead(afterClearance)
                let elapsed = Int((current.capturedAt.timeIntervalSince(eventAt) * 1000).rounded())
                switch settle.take(current, elapsedMilliseconds: elapsed) {
                case .readAgain:
                    continue
                case let .settled(served):
                    return try observation(served, reason: nil, reads: settle.reads, in: Call(action: action, window: window, before: before, eventAt: eventAt, bound: settleMilliseconds))
                case let .unsettled(served, reason):
                    return try observation(served, reason: reason, reads: settle.reads, in: Call(action: action, window: window, before: before, eventAt: eventAt, bound: settleMilliseconds))
                }
            }
        }
    }

    /// A tap at `point`, then `frames` captures as fast as capture goes, each read once the last is taken.
    ///
    /// Focus is re-checked before every frame; a refusal ends the burst, is recorded in the result and leaves the frames before it standing. Any other error ends the call and removes the burst's directory.
    public func burst(at point: MirrorFraction, frames: Int) throws -> MirrorBurst {
        try lock.withLock {
            store.clearScratch()
            _ = try seams.clear()
            let window = try seams.window()
            var afterClearance = try seams.perform(.tap(point), window, seams.recheck(.beforeAction))
            let tappedAt = seams.now()
            let directory = try store.burstDirectory(label: MirrorAction.tap(point).label, at: tappedAt)
            var finished = false
            defer {
                if !finished {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
            var captured: [Capture] = []
            var stoppedBy: MirrorFocusRefusal?
            for index in stride(from: 1, through: frames, by: 1) {
                do {
                    afterClearance = try seams.recheck(.beforeFrame(index))
                } catch let refusal as MirrorFocusRefusal {
                    stoppedBy = refusal
                    break
                }
                let file = directory.appendingPathComponent(String(format: "f%02d.png", index))
                try seams.capture(window, file, afterClearance)
                let taken = seams.now()
                captured.append(Capture(index: index, file: file, takenAt: taken, milliseconds: Int((taken.timeIntervalSince(tappedAt) * 1000).rounded())))
            }
            let read = try captured.map { frame in
                try MirrorBurst.Frame(index: frame.index, millisecondsSinceTap: frame.milliseconds, read: seams.read(frame.file, frame.takenAt))
            }
            try store.prune()
            finished = true
            return MirrorBurst(point: point, window: window, requested: frames, frames: read, stoppedBy: stoppedBy, directory: directory)
        }
    }

    /// Keeps the served capture under its name and builds the observation around it.
    private func observation(_ served: MirrorRead, reason: MirrorSettle.Reason?, reads: Int, in call: Call) throws -> MirrorObservation {
        let label = call.action?.label ?? "read"
        let kept = try store.keep(served.path, label: label, at: served.capturedAt)
        let read = MirrorRead(path: kept, pixelSize: served.pixelSize, capturedAt: served.capturedAt, lines: served.lines)
        return MirrorObservation(action: call.action, window: call.window, before: call.before, read: read, reason: reason, eventAt: call.eventAt, reads: reads, boundMilliseconds: call.bound)
    }

    /// An action's fractions checked against the window's shape (``MirrorWindowFrame/target(for:)``) before anything is captured.
    ///
    /// A point off the phone's screen is a bad argument, so it is refused before the before-read spends a capture and OCR on a call that cannot post. The poster checks again; this only makes the refusal cheap.
    private static func refuseOffScreen(_ action: MirrorAction, in window: MirrorWindowFrame) throws {
        switch action {
        case let .tap(point), let .scroll(_, _, point):
            _ = try window.target(for: point)
        case let .swipe(start, end, _):
            _ = try window.target(for: start)
            _ = try window.target(for: end)
        case .menu:
            break
        }
    }

    /// The real post for each action: the poster's guarded gestures, or the menu click, which has no after-check.
    private static func post(_ action: MirrorAction, in window: MirrorWindowFrame, focus: MirrorFocusGuard, clearance: MirrorFocus.Clearance) throws -> MirrorFocus.Clearance {
        let poster = MirrorPoster(window: window, focus: focus)
        switch action {
        case let .tap(point):
            return try poster.tap(at: point, clearance: clearance)
        case let .swipe(start, end, milliseconds):
            return try poster.drag(from: start, to: end, milliseconds: milliseconds, clearance: clearance)
        case let .scroll(lines, horizontal, point):
            return try poster.scroll(lines: lines, horizontal: horizontal, at: point, clearance: clearance)
        case let .menu(item):
            try MirrorMenu().click(item, clearance: clearance)
            return clearance
        }
    }
}

extension MirrorStepRunner {
    /// Everything the runner does to the Mac, so a test scripts it.
    struct Seams {
        /// Activates Mirroring and clears or refuses (``MirrorFocusGuard/clear()``).
        var clear: () throws -> MirrorFocus.Clearance
        /// One focus read, no activation: just before the event, and before a burst's frame.
        var recheck: (MirrorFocusRefusal.Moment) throws -> MirrorFocus.Clearance
        /// The window as it is now.
        var window: () throws -> MirrorWindowFrame
        /// Posts `action` at `window` and answers the clearance to capture on: the poster's after-check for a gesture, the clearance itself for a menu click.
        var perform: (MirrorAction, MirrorWindowFrame, MirrorFocus.Clearance) throws -> MirrorFocus.Clearance
        /// Captures `window` to the file.
        var capture: (MirrorWindowFrame, URL, MirrorFocus.Clearance) throws -> Void
        /// Reads the PNG at the file, taken at the date.
        var read: (URL, Date) throws -> MirrorRead
        /// The time now.
        var now: () -> Date
        /// Waits that many seconds.
        var pause: (TimeInterval) -> Void
    }
}

private extension MirrorStepRunner {
    /// What a step knew before it settled: what the observation reports besides the served read.
    struct Call {
        let action: MirrorAction?
        let window: MirrorWindowFrame
        let before: MirrorRead?
        let eventAt: Date
        let bound: Int
    }

    /// One burst frame captured, awaiting its read.
    struct Capture {
        let index: Int
        let file: URL
        let takenAt: Date
        let milliseconds: Int
    }
}
