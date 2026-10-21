//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore

/// `simwalk bundle diff <reference.simwalk> <run.simwalk>` — the differ over two bundles: what changed in form between two walks, with a crop of the screenshot for each flag.
struct BundleDiffCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diff",
        abstract: "Compare a run bundle against a reference bundle by form, never value: sections present, in order and in place. Each form flag names a crop of the screenshot that shows it; --crops writes them as PNGs. Exits 2 on any flag the reference lacks (flags both sides carry are reported apart and not counted), any screen or state on one side only, and any screen or tree not compared."
    )

    @Argument(help: ArgumentHelp("Path to the reference capture bundle.", valueName: "reference"))
    var referencePath: String

    @Argument(help: ArgumentHelp("Path to the capture bundle compared against it.", valueName: "run"))
    var runPath: String

    @Option(name: .long, help: ArgumentHelp("Write one PNG per flag crop into this directory, which must be new or empty.", valueName: "dir"))
    var crops: String?

    @Option(name: .long, help: JUnitOutput.help)
    var junit: String?

    func validate() throws {
        try JUnitOutput.validate(junit)
    }

    func run() throws {
        try run(log: .standard(), emit: StandardStreams.emit, emitError: StandardStreams.emitError, isStdoutPiped: StandardStreams.isStdoutPiped)
    }

    /// The same run with its effects injectable, for the reason `TimedCall` takes them.
    func run(log: UsageLog, emit: (String) -> Void, emitError: (String) -> Void, isStdoutPiped: () -> Bool = { false }) throws {
        let output = JUnitOutput.make(junit, command: "bundle diff")
        try TimedCall.run(tool: "bundle diff", target: runPath, log: log, emit: emit, emitError: emitError, defaultFailureKind: .toolError, isStdoutPiped: isStdoutPiped, junit: output) { try answer(junit: output) }
    }

    /// The answer, without the printing — what the MCP face serves, so one verb cannot come to answer differently depending on which face asked.
    ///
    /// The crops directory is checked before either bundle is read: a refusal that costs nothing comes first.
    ///
    /// `junit` is handed the same flags as test cases, for the CLI's `--junit`; the MCP face passes none.
    func answer(junit: JUnitOutput? = nil) throws -> Answer {
        let directory = crops.map { URL(fileURLWithPath: $0).standardizedFileURL }
        if let directory {
            try BundleDiffCrops.requireFresh(directory)
        }
        let referenceBundle = try CaptureBundle.read(at: URL(fileURLWithPath: referencePath))
        let runBundle = try CaptureBundle.read(at: URL(fileURLWithPath: runPath))
        if let refusal = BundleDiff.animationsRefusal(run: runBundle.manifest, reference: referenceBundle.manifest) {
            throw BundleDiffError.animationsDiffer(message: refusal)
        }
        let diff = BundleDiff.compare(run: runBundle, against: referenceBundle)
        junit?.report = JUnitDiffCases.report(diff)
        let written = try directory.map { try BundleDiffCrops.write(diff, reference: referenceBundle, run: runBundle, into: $0) }
        return BundleDiffSummary(diff, reference: referenceBundle, run: runBundle, crops: written).answer()
    }
}
