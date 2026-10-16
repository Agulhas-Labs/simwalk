//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkDriver

/// Every seam of a `MirrorStepRunner` scripted: reads taken from a list, a clock that moves only when the runner pauses, captures that write a one-byte file, and a log of what was asked in order.
///
/// A class, because the seams are closures over one shared log and clock.
final class MirrorStepScript {
    /// A screen with a clock in the status band and a body of lines below it (the core suites' `MirrorReadFixture`, which this target cannot see).
    static func screen(_ body: [String]) -> MirrorRead {
        let clock = MirrorTextLine(text: "09:41", centreX: 0.5, centreY: 0.02, width: 0.3, height: 0.02, confidence: 0.9)
        let lines = body.enumerated().map { MirrorTextLine(text: $1, centreX: 0.5, centreY: 0.3 + Double($0) * 0.1, width: 0.3, height: 0.02, confidence: 0.9) }
        return MirrorRead(path: URL(fileURLWithPath: "/tmp/x.png"), pixelSize: nil, capturedAt: Date(timeIntervalSince1970: 0), lines: [clock] + lines)
    }

    private(set) var log: [String] = []
    /// Whether the call lock was held at every step the runner took through a seam.
    private(set) var lockHeldAtEveryStep = true

    private let reads: [MirrorRead]
    private let clearError: Error?
    private let failingReadNumber: Int?
    private let recheckRefusalAt: Int?
    private let actionRecheckFrontmost: String?
    private var readCount = 0
    private var elapsed: TimeInterval = 0
    private var lockFile: URL?

    /// - Parameters:
    ///   - reads: Served in order, the last repeating; each gets the file and time it was asked for.
    ///   - clearError: What the guard throws, if anything.
    ///   - failingReadNumber: The read, counted from 1, that throws.
    ///   - recheckRefusalAt: The burst frame, counted from 1, whose focus check is refused.
    ///   - actionRecheckFrontmost: What the read just before the event names instead of Mirroring, if anything.
    init(reads: [MirrorRead], clearError: Error? = nil, failingReadNumber: Int? = nil, recheckRefusalAt: Int? = nil, actionRecheckFrontmost: String? = nil) {
        self.reads = reads
        self.clearError = clearError
        self.failingReadNumber = failingReadNumber
        self.recheckRefusalAt = recheckRefusalAt
        self.actionRecheckFrontmost = actionRecheckFrontmost
    }

    /// The lock under `root`, remembered so each step can check it is held.
    func lock(_ root: URL) -> MirrorCallLock {
        let lock = MirrorCallLock(root: root)
        lockFile = lock.file
        return lock
    }

    /// Whether no call holds the lock right now: a non-blocking attempt on it succeeds.
    func lockIsFree(_ root: URL) -> Bool {
        let descriptor = open(MirrorCallLock(root: root).file.path, O_RDWR | O_CREAT, 0o600)
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return false }
        flock(descriptor, LOCK_UN)
        return true
    }

    var seams: MirrorStepRunner.Seams {
        MirrorStepRunner.Seams(
            clear: { [self] in
                step("clear")
                if let clearError {
                    throw clearError
                }
                return try MirrorFocus.recheck(MirrorFocus.appName, at: .beforeAction)
            },
            recheck: { [self] moment in
                if moment == .beforeAction {
                    step("recheck action")
                    return try MirrorFocus.recheck(actionRecheckFrontmost ?? MirrorFocus.appName, at: moment)
                }
                guard case let .beforeFrame(frame) = moment else { throw MirrorFocusRefusal(frontmost: "?", moment: moment) }
                step("recheck \(frame)")
                if frame == recheckRefusalAt {
                    throw MirrorFocusRefusal(frontmost: "Safari", moment: moment)
                }
                return try MirrorFocus.recheck(MirrorFocus.appName, at: moment)
            },
            window: { [self] in
                step("window")
                return MirrorWindowFrame(windowID: 7, x: 0, y: 0, width: 383, height: 843)
            },
            perform: { [self] action, _, clearance in
                step("perform \(action.label)")
                return clearance
            },
            capture: { [self] _, file, _ in
                step("capture")
                try Data("x".utf8).write(to: file)
            },
            read: { [self] file, date in
                step("read")
                readCount += 1
                if readCount == failingReadNumber {
                    throw ReadFailure()
                }
                let scripted = reads[min(readCount, reads.count) - 1]
                return MirrorRead(path: file, pixelSize: scripted.pixelSize, capturedAt: date, lines: scripted.lines)
            },
            now: { [self] in Date(timeIntervalSince1970: 1_760_000_000 + elapsed) },
            pause: { [self] seconds in
                step("pause \(seconds)")
                elapsed += seconds
            }
        )
    }

    private func step(_ name: String) {
        log.append(name)
        if let lockFile, lockIsFree(lockFile.deletingLastPathComponent().deletingLastPathComponent()) {
            lockHeldAtEveryStep = false
        }
    }
}

extension MirrorStepScript {
    /// The read failing on purpose.
    struct ReadFailure: Error, Equatable {}
}
