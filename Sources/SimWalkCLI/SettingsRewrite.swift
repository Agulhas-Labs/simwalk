//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// Every rewrite of a Claude Code `settings.json` this tool makes, through the shared Fieldwork writer: a symlinked settings file is written through (its target changes, and the link stays a link), and the backup is written atomically beside the file that changed.
struct SettingsRewrite {
    /// Replaces the file `settings` leads to with `updated`, keeping `original` beside it before this run's first rewrite and never again.
    ///
    /// A second step editing the same file in the same run would otherwise back up what the first step already edited, overwriting the pristine copy. A backup that could not be kept is said on the verdict.
    static func write(_ updated: Data, to settings: URL, original: Data?, backedUp: inout Bool, qualifications: inout [String]) throws {
        let keep = backedUp ? nil : original
        if let note = try SettingsFile.rewrite(settings, with: updated, original: keep, tool: .simwalk) {
            qualifications.append(note)
        }
        if let original, !original.isEmpty {
            backedUp = true
        }
    }
}
