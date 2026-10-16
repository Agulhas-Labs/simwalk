//
// Copyright © Agulhas Labs
//

import ArgumentParser

/// `simwalk session …` — a resident runner held on one device, so an agent exploring an app reads it warm instead of paying a runner launch per look.
///
/// Sessions are for exploring; a walk stays the reproducible record.
struct SessionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "session",
        abstract: "Start, read, step, save, end and list live sessions: a resident runner on one device, read and stepped warm, and saved as a walkbook screen.",
        subcommands: [SessionStartCommand.self, SessionReadCommand.self, SessionStepCommand.self, SessionSaveCommand.self, SessionEndCommand.self, SessionListCommand.self]
    )
}
