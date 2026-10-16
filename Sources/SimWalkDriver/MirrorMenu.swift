//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Clicks one of iPhone Mirroring's View menu items through System Events: navigation without a keystroke (Brief §8 "Never keystrokes").
///
/// The click names the process, so it reaches Mirroring's own menu bar whatever is frontmost; it still takes a clearance, because the screen it changes is the one the guard vouched for. Typing-free, and reliable on 14 Oct.
public struct MirrorMenu {
    private let shell: Shell

    public init(shell: Shell = Shell()) {
        self.shell = shell
    }

    /// Clicks `item`, refused naming it when `osascript` fails — the item missing in this language, say, or System Events not allowed to drive the menu.
    public func click(_ item: MirrorMenuItem, clearance _: MirrorFocus.Clearance) throws {
        let script = "tell application \"System Events\" to tell process \"\(MirrorFocus.appName)\" to click menu item \"\(item.title)\" of menu \"View\" of menu bar 1"
        let result = try shell.run("/usr/bin/osascript", ["-e", script], timeout: 10)
        guard result.succeeded else {
            throw MirrorControlError.noMenuItem(title: item.title, reason: result.failureLine)
        }
    }
}
