//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk session save <id> --screen <screen id> --into <walkbook.json> [--expect <identifier>] [--since <request n>]` — what the session did, written as a walkbook screen a walk replays.
///
/// **Before `end`**: the route is read from the session's responses, and `end` removes the session's directory with them. See ``LiveSessionSave`` for what is saved and how it is written.
struct SessionSaveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "save",
        abstract: "Save what a live session did as a walkbook screen: the steps that landed, under the state it launched in. Before `session end`."
    )

    @Argument(help: "The session id `session start` printed.")
    var id: String

    @Option(name: .long, help: "The id the saved screen takes in the walkbook.")
    var screen: String

    @Option(name: .long, help: "The walkbook to save into: created when it does not exist; otherwise the screen is appended and the file re-encoded.")
    var into: String

    @Option(name: .long, help: "The accessibility identifier the reached screen carries — the walkbook's `expect`, checked on every capture.")
    var expect: String?

    @Option(name: .long, help: "Save only the steps from this request on (requests count from 1 in the session; the answer names each saved step's request). Omit for every step since launch.")
    var since: Int?

    func validate() throws {
        if let since, since < 1 {
            throw ValidationError("--since \(since) names no request — requests count from 1")
        }
    }

    func run() throws {
        try TimedCall.run(tool: "session save", target: id, defaultFailureKind: .toolError) {
            try perform()
        }
    }

    func perform(store: LiveSessionStore = .standard(), leases: LeaseStore = .standard(), now: () -> Date = { Date() }) throws -> Answer {
        guard let record = store.record(id: id) else {
            throw LiveSessionHostError.unknownSession(id: id)
        }
        // A save is a session command: it renews a device session's lease as `read` does, and refuses when it cannot.
        try LiveSessionDeviceExchange(record: record, store: store, leases: leases)?.renewLease(now: now)
        return try LiveSessionSave(screenID: screen, expect: expect, since: since).perform(
            sessionID: id,
            channel: LiveSessionChannel(layout: store.layout(id: id)),
            foundAppearance: record.foundAppearance,
            into: URL(fileURLWithPath: into)
        )
    }
}
