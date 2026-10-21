//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk bundle labels <path>` — what a bundle holds for each App Store Accessibility Nutrition Label claim, and what is still missing (SimWalk#163).
///
/// A report for a person preparing a submission, so it has no MCP twin: an agent audits with `bundle audit`.
struct BundleLabelsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "labels",
        abstract: "Report what a bundle holds, fails and lacks for each Accessibility Nutrition Label claim, each missing item as the walkbook change to make."
    )

    @Argument(help: "Path to a capture bundle directory.")
    var bundle: String

    @Option(name: .long, help: ArgumentHelp("Report only these claims, comma-separated. Claims: \(AccessibilityLabelClaim.names).", valueName: "claims"))
    var claim: String?

    /// A claim nobody wrote is refused before anything is read, naming the ones that exist.
    func validate() throws {
        if let unknown = requested.first(where: { AccessibilityLabelClaim(rawValue: $0) == nil }) {
            throw ValidationError("'\(unknown)' is not an Accessibility Nutrition Label claim — the claims are \(AccessibilityLabelClaim.names)")
        }
    }

    private var requested: [String] {
        claim.map { $0.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) } } ?? []
    }

    func run() throws {
        try run(log: .standard(), emit: StandardStreams.emit, emitError: StandardStreams.emitError, isStdoutPiped: StandardStreams.isStdoutPiped)
    }

    /// The same run with its effects injectable, for `BundleAuditCommand`'s reason: the contract is an exit code, checkable only against the command itself.
    func run(log: UsageLog, emit: (String) -> Void, emitError: (String) -> Void, isStdoutPiped: () -> Bool = { false }) throws {
        try TimedCall.run(tool: "bundle labels", target: bundle, log: log, emit: emit, emitError: emitError, defaultFailureKind: .toolError, isStdoutPiped: isStdoutPiped) {
            try answer()
        }
    }

    /// The answer, without the printing.
    func answer() throws -> Answer {
        let opened = try CaptureBundle.read(at: URL(fileURLWithPath: bundle))
        let claims = requested.compactMap(AccessibilityLabelClaim.init(rawValue:))
        return try BundleLabelsSummary(BundleLabels(opened, claims: claims, recognizer: VisionTextReader()).run(), of: opened).answer()
    }
}
