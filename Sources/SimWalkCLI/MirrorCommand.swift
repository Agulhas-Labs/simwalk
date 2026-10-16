//
// Copyright © Agulhas Labs
//

import ArgumentParser

/// `simwalk mirror …` — a real iPhone, driven through macOS's iPhone Mirroring window with guarded mouse and wheel events and observed as OCR text (SimWalk#113, Brief §8).
///
/// Every verb re-activates Mirroring and refuses, with exit 3, unless it is frontmost: the one refusal a caller should retry.
struct MirrorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mirror",
        abstract: "Drive a real iPhone through iPhone Mirroring and read it as OCR text: read, tap, swipe, scroll, menu, burst.",
        subcommands: [MirrorReadCommand.self, MirrorTapCommand.self, MirrorSwipeCommand.self, MirrorScrollCommand.self, MirrorMenuCommand.self, MirrorBurstCommand.self]
    )
}
