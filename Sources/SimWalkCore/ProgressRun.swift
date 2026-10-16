//
// Copyright © Agulhas Labs
//

import Foundation

/// The host's hold on a run's progress: when it goes away with the run not ended, the file is ended as `failed`, error `interrupted` (`Docs/SIMWALK-PROGRESS.md` §3).
///
/// A guard rather than the writer's own `deinit`, because the runner holds a writer too and never ends the run — the host does — so a writer going away says nothing about the run. Best effort, and knowingly so: a run killed outright runs no code at all, which is why a reader's real protection is the file's `pid` and `updatedAt`, not this.
public final class ProgressRun: Sendable {
    public let writer: ProgressWriter
    /// The run's hold on its files, released only once `deinit` has written — so no run that claims the slot next can have its file overwritten by this one's end.
    private let claim: ProgressClaim?

    public init(writer: ProgressWriter, claim: ProgressClaim? = nil) {
        self.writer = writer
        self.claim = claim
    }

    deinit {
        writer.interrupt()
    }
}
