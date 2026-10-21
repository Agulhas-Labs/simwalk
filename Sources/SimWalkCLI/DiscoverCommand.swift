//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk discover --app <bundle id> (--lease <token> | --device <udid>) [--depth N] [--max-screens N] --output <draft.walkbook.json>` — crawls the app's tab bar buttons, disclosure rows and back button through a live session of its own, and writes the screens it reached as a draft walkbook.
///
/// **The session is the verb's own**: started as `session start` starts one, with the same device options, and ended — the device handed back, any lease the start took released — on every way out: an answer, a refusal, a throw from the crawl, or a SIGINT or SIGTERM.
///
/// The crawl is ``DiscoverCrawl``; this face starts the session, drives it through ``LiveDiscoverySession`` and writes the draft, refusing a `--output` that already exists.
struct DiscoverCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "discover",
        abstract: "Crawl a running app's tabs and disclosure rows through a live session and write the screens reached as a draft walkbook."
    )

    @Option(name: .long, help: "The bundle identifier of the installed app to crawl.")
    var app: String

    @Option(name: .long, help: "The UDID of a booted simulator that is yours, or of a paired physical iPhone or iPad (then --team is required), as `session start` takes it.")
    var device: String?

    @Option(name: .long, help: "A lease token from `simwalk lease acquire`: run on the leased device.")
    var lease: String?

    @Option(name: .long, help: "A capture state as JSON (a walkbook's `states` entry) to launch the app under; every drafted screen carries it.")
    var state: String?

    @Option(name: .long, help: "How many disclosure-row taps from a tab (or the launch screen) to follow.")
    var depth = DiscoverCrawl.defaultDepth

    @Option(name: .long, help: "The most screens the draft holds.")
    var maxScreens = DiscoverCrawl.defaultMaxScreens

    @Option(name: .long, help: "Where to write the draft walkbook; refused when the file already exists.")
    var output: String

    @Option(name: .long, help: "Physical device only, and required there: the Apple signing team ID the runner is built under.")
    var team: String?

    @Option(name: .long, help: "Physical device only: the runner's bundle identifier, when the default is not one your team can sign.")
    var runnerBundleId: String?

    @Flag(name: .long, help: "Keep UIKit animations on in the app. A simulator session switches them off by default so screens settle sooner.")
    var animations = false

    func validate() throws {
        try start.validate()
        guard depth >= 0 else { throw ValidationError("--depth \(depth): pass 0 or more") }
        guard maxScreens >= 1 else { throw ValidationError("--max-screens \(maxScreens): pass 1 or more") }
    }

    func run() throws {
        LaunchedBinary.capture()
        let cancellation = Cancellation()
        let signals = TerminationSignals(cancelling: cancellation)
        defer { withExtendedLifetime(signals) {} }
        try TimedCall.run(tool: "discover", target: app, defaultFailureKind: .runnerFailed) {
            try perform(builds: .standard(), cancellation: cancellation, animationsLibrary: WalkCommand.standardAnimationsLibrary(), note: StandardStreams.emitError)
        }
    }

    /// The session start this verb makes: its own device, state and runner options, as `session start` would take them.
    var start: SessionStartCommand {
        var start = SessionStartCommand()
        start.app = app
        start.device = device
        start.lease = lease
        start.state = state
        start.team = team
        start.runnerBundleId = runnerBundleId
        start.animations = animations
        return start
    }

    /// Starts the session, crawls it, writes the draft and ends the session — every effect injectable, as `session start`'s are.
    func perform(
        shell: Shell = Shell(),
        pause: @escaping (TimeInterval) -> Void = Thread.sleep(forTimeInterval:),
        now: @escaping () -> Date = { Date() },
        id: () -> String = { String(UUID().uuidString.prefix(8)).lowercased() },
        runner: (() throws -> RunnerSource)? = nil,
        logFileURL: URL = UsageLog.standard().fileURL,
        builds: RunnerBuilds,
        leases: LeaseStore = .standard(),
        store: LiveSessionStore = .standard(),
        processes: any LiveSessionProcesses = LiveSessionSystemProcesses(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        cancellation: Cancellation? = nil,
        deviceHello: ((DeviceSessionBind) throws -> LiveSessionReady)? = nil,
        deviceSend: LiveSessionDeviceExchange.Send? = nil,
        animationsLibrary: WalkCommand.AnimationsLibrary? = nil,
        note: (String) -> Void = { _ in }
    ) throws -> Answer {
        let url = URL(fileURLWithPath: output)
        // Refused before a runner is built or the device touched; the write's exclusive rename checks again.
        guard !FileManager.default.fileExists(atPath: url.path) else { throw DiscoverError.outputExists(path: output) }
        let sessionID = id()
        let started = try start.perform(
            shell: shell, pause: pause, now: now, id: { sessionID }, runner: runner, logFileURL: logFileURL, builds: builds, leases: leases, store: store,
            processes: processes, environment: environment, cancellation: cancellation, deviceHello: deviceHello, animationsLibrary: animationsLibrary, note: note
        )
        let end = SessionEnding {
            try SessionEndCommand.parse([sessionID]).perform(store: store, processes: processes, leases: leases, shell: shell, pause: pause, now: now)
        }
        cancellation?.onCancel { _ = try? end.once() }
        let crawled: Answer
        do {
            guard let record = store.record(id: sessionID) else { throw LiveSessionHostError.unknownSession(id: sessionID) }
            let session = LiveDiscoverySession(record: record, store: store, processes: processes, leases: leases, shell: shell, deviceSend: deviceSend, cancellation: cancellation, pause: pause, now: now)
            crawled = try crawl(session, header: started.header, url: url)
        } catch {
            _ = try? end.once()
            throw error
        }
        guard let ended = try end.once() else { return crawled }
        let handback = ended.verdict.isQualified ? ended.residue : []
        return Answer(header: crawled.header, verdict: Self.qualifications(of: ended.verdict).reduce(crawled.verdict) { $0.adding(qualification: $1) }, residue: crawled.residue + handback)
    }

    /// Crawls `session` in the state it was launched under — or, launched plain, the appearance the device was found in, as `session save` drafts — and writes the draft.
    private func crawl(_ session: LiveDiscoverySession, header: String, url: URL) throws -> Answer {
        let launch = try LiveSessionChannel(layout: session.store.layout(id: session.record.id)).launch()
        guard let state = launch?.state ?? session.record.foundAppearance.map({ Walkbook.CaptureState(theme: $0) }) else { throw DiscoverError.noState }
        let result = try DiscoverCrawl(appBundleID: app, state: state, depth: depth, maxScreens: maxScreens).run(on: session)
        try result.write(to: url)
        return result.answer(header: header.replacingOccurrences(of: "live session:", with: "discover:"), output: output)
    }

    private static func qualifications(of verdict: AnswerVerdict) -> [String] {
        if case let .qualified(qualifications, _) = verdict {
            return qualifications
        }
        return []
    }
}
