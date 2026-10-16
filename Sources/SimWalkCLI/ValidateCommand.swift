//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore

/// `simwalk validate <walkbook.json>` — answers whether a walkbook can be walked, before a simulator is booted for it.
struct ValidateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Check that a walkbook parses and can be executed as written."
    )

    @Argument(help: "Path to a walkbook JSON file.")
    var walkbook: String

    @Flag(name: .long, help: "Apply the device target's rules too (`walk --device <physical udid>`): whatever a device walk would refuse — a locale, a location, resetPermissions, a walk-level setup — is a problem here.")
    var device = false

    func run() throws {
        try run(log: .standard(), emit: StandardStreams.emit, emitError: StandardStreams.emitError, isStdoutPiped: StandardStreams.isStdoutPiped) { try answer() }
    }

    /// The same run with its three effects and the answer itself injectable, so the kind an unmapped failure records can be checked without a walkbook that could produce one.
    ///
    /// Every failure of the walkbook argument is a `WalkbookLoadError`, classified on its own account; what is left is this command's own code over a walkbook it has already loaded — hashing it for the header — so an unmapped failure here is `tool-error`, never a caller's mistake.
    func run(log: UsageLog, emit: (String) -> Void, emitError: (String) -> Void, isStdoutPiped: () -> Bool = { false }, body: () throws -> Answer) throws {
        try TimedCall.run(tool: "validate", target: walkbook, log: log, emit: emit, emitError: emitError, defaultFailureKind: .toolError, isStdoutPiped: isStdoutPiped, body: body)
    }

    /// The answer, without the printing — what the MCP face serves, so one verb cannot come to answer differently depending on which face asked.
    func answer() throws -> Answer {
        let url = URL(fileURLWithPath: walkbook)
        let book = try WalkbookLoader.load(contentsOf: url)
        let unsupported = device ? DeviceTargetSupport.unsupported(in: book) : []
        guard unsupported.isEmpty else {
            throw WalkbookLoadError.invalid(source: url.standardizedFileURL.path, problems: unsupported.map(WalkbookProblem.unsupportedOnDevice))
        }
        return try WalkbookSummary(book, onDevice: device).answer()
    }
}
