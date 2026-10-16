//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk device walk <walkbook> --udid <udid> --team <TEAM> --output <path>` — walks a walkbook on a physical iPhone or iPad and leaves an ordinary capture bundle on the Mac (SimWalk#116).
///
/// A thin alias of `walk --device` (SimWalk#116 next step 4): it parses its own flags and runs ``DeviceWalk``, the path both share.
struct DeviceWalkCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "walk",
        abstract: "Walk a walkbook on a physical iPhone or iPad and copy the capture bundle back."
    )

    @Argument(help: "The walkbook JSON file.")
    var walkbook: String

    @Option(name: .customLong("udid"), help: "The iPhone's or iPad's UDID, as `xcrun devicectl list devices` shows it. The walk leases it for its length; pass this or --lease.")
    var requestedUDID: String?

    @Option(help: "The token of a lease on the phone (`simwalk lease acquire --physical <udid>`); the lease names the device. The walk renews it and leaves it to its holder.")
    var lease: String?

    @Option(help: "The Apple signing team ID the runner is built under.")
    var team: String?

    @Option(help: "The runner's bundle identifier, when the default is not one your team can sign.")
    var runnerBundleId: String?

    @Option(help: "A built `.app` of the walkbook's app to install on the phone first (replacing its copy, not restored). Its build hash is taken on this Mac and recorded as installed, not read back; without it the build is `device-unread`.")
    var app: String?

    @Option(help: "Where the capture bundle is written (a fresh `.simwalk` path).")
    var output: String

    func validate() throws {
        if requestedUDID != nil, lease != nil {
            throw ValidationError("pass --udid or --lease, not both — a lease names its device")
        }
        if requestedUDID == nil, lease == nil {
            throw ValidationError("pass --udid <udid> (the walk leases the phone itself) or --lease <token> (a lease from `simwalk lease acquire --physical <udid>`)")
        }
    }

    func run() throws {
        try run(log: .standard(), emit: StandardStreams.emit, emitError: StandardStreams.emitError) {
            try aliasAnswer(shell: Shell(), builds: .standard(), resolveRunner: nil, leases: .standard(), holderPID: getpid(), now: Date())
        }
    }

    /// The same run with its effects and the walk itself injectable, so a test can check what a refusal prints without a phone.
    func run(log: UsageLog, emit: (String) -> Void, emitError: (String) -> Void, answering: () throws -> Answer) throws {
        try TimedCall.run(tool: "device walk", target: walkbook, log: log, emit: emit, emitError: emitError, defaultFailureKind: .runnerFailed, refusalClosing: Self.aliasLine, body: answering)
    }

    /// What the alias serves: ``answer(shell:builds:resolveRunner:leases:holderPID:now:)`` with ``aliasLine`` last.
    func aliasAnswer(shell: Shell, builds: RunnerBuilds, resolveRunner: (() throws -> RunnerSource)?, leases: LeaseStore, holderPID: Int32, now: Date) throws -> Answer {
        try answer(shell: shell, builds: builds, resolveRunner: resolveRunner, leases: leases, holderPID: holderPID, now: now).appending(Self.aliasLine)
    }

    /// The last line of the alias's answer: the verb is `walk --device` now (SimWalk#116).
    static var aliasLine: String {
        "device walk is walk --device now"
    }

    /// The answer, with the shell, the runner builds and the runner resolution injectable.
    ///
    /// That makes the order of commands checkable without a phone. It is ``DeviceWalk/answer(shell:builds:resolveRunner:leases:holderPID:now:)``, the path `walk --device` takes.
    func answer(shell: Shell, builds: RunnerBuilds, resolveRunner: (() throws -> RunnerSource)?, leases: LeaseStore, holderPID: Int32, now: Date = Date()) throws -> Answer {
        let walk = DeviceWalk(walkbook: walkbook, requestedUDID: requestedUDID, lease: lease, team: team, runnerBundleID: runnerBundleId, app: app, output: output, screens: [], settle: nil, motion: false)
        return try walk.answer(shell: shell, builds: builds, resolveRunner: resolveRunner, leases: leases, holderPID: holderPID, now: now)
    }
}

private extension Answer {
    /// This answer with `line` as its last.
    func appending(_ line: String) -> Answer {
        Answer(header: header, verdict: verdict, residue: residue + [line], weighing: weighing)
    }
}
