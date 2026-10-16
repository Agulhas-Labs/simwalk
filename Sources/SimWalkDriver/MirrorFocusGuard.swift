//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// The focus guard's live half: activates iPhone Mirroring, then polls System Events through ``MirrorFocus`` until it clears or refuses (Brief §8 "The guard").
///
/// The three things it does to the Mac — activate, read the frontmost process, wait — are injected, so a test scripts the names and the waits, and sees that a refusal leaves nothing posted.
///
/// **Activation and the frontmost read both go through an `osascript` child.** An in-process `NSAppleScript` measured about 30 ms a read from a synchronous caller, but `simwalk` runs its commands off the main thread, where the same call blocked for 3–30 s a read (sampled live on 14 Oct: the whole wait inside `-[NSAppleScript _executeWithMode:andReturnError:]`); an `osascript` spawn costs 140–410 ms and never blocked. Activation is paid once a call, and `osascript … to activate` is the route the spike proved steals focus back from a background command line, where `NSRunningApplication.activate` may be refused by cooperative activation.
public struct MirrorFocusGuard {
    private let activate: () -> Void
    private let readFrontmost: () throws(MirrorControlError) -> String
    private let pause: (TimeInterval) -> Void

    /// The live guard: it activates Mirroring, reads System Events and sleeps the thread.
    public init() {
        self.init(activate: Self.activateMirroring, readFrontmost: Self.frontmostProcess, pause: Thread.sleep(forTimeInterval:))
    }

    /// A guard over scripted activation, reads and waits.
    init(activate: @escaping () -> Void, readFrontmost: @escaping () throws(MirrorControlError) -> String, pause: @escaping (TimeInterval) -> Void) {
        self.activate = activate
        self.readFrontmost = readFrontmost
        self.pause = pause
    }

    /// Activates Mirroring and polls until it is frontmost: a clearance for the action, or a refusal before anything is posted naming what was frontmost.
    public func clear() throws -> MirrorFocus.Clearance {
        activate()
        var focus = MirrorFocus()
        while true {
            pause(MirrorFocus.pollInterval)
            switch try focus.take(readFrontmost()) {
            case let .cleared(clearance):
                return clearance
            case .pollAgain:
                continue
            case let .refused(frontmost):
                throw MirrorFocusRefusal(frontmost: frontmost, moment: .beforeAction)
            }
        }
    }

    /// One read, no activation and no polling: just before the event, after a gesture's last event, or before a burst's frame.
    ///
    /// Activating again here would hide the very focus change the check is for.
    public func recheck(at moment: MirrorFocusRefusal.Moment) throws -> MirrorFocus.Clearance {
        try MirrorFocus.recheck(readFrontmost(), at: moment)
    }

    /// Asks Mirroring to come to the front.
    ///
    /// Its outcome is not read: the poll that follows is the only judge, and refuses naming what came forward instead.
    private static func activateMirroring() {
        _ = try? Shell().run("/usr/bin/osascript", ["-e", "tell application \"\(MirrorFocus.appName)\" to activate"], timeout: 10)
    }

    /// The frontmost process's name from System Events, read through an `osascript` child.
    ///
    /// A failed read — `osascript` exiting non-zero, as it does when Automation of System Events is not granted — is refused as that, never as lost focus: an empty name would read as "retry", which no retry would fix.
    private static func frontmostProcess() throws(MirrorControlError) -> String {
        let result: Shell.Result
        do {
            result = try Shell().run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to get name of first process whose frontmost is true"], timeout: 10)
        } catch {
            throw .systemEventsUnavailable(reason: String(describing: error))
        }
        guard result.status == 0 else {
            throw .systemEventsUnavailable(reason: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
