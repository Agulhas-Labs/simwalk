//
// Copyright © Agulhas Labs
//

import Foundation

/// What `walk --dry-run` writes: every screen's route followed against the app, and nothing captured — a plain JSON file the runner writes and the host reads back.
///
/// **Not a capture bundle, deliberately.** A manifest with no captures is one `finalise` refuses, and it would be right to: a bundle attests to screens it holds, and a dry run holds none. So the probe has its own shape, its own reader and its own rendering (``RouteProbeSummary``), and nothing that reads bundles can mistake one for a walk.
///
/// **Held to the walkbook it was run from, on both sides.** The writer refuses a report the reader would refuse — a screen missing, out of order, carrying a route other than the walkbook's, or stopping at a step the route does not have — which is the manifest's "a bundle cannot be created in a state that reading it would reject" applied to the second artefact. The host compares against the walkbook it handed the runner, so a report left by another walkbook is refused rather than rendered.
///
/// **And held to the run that read it (SimWalk#36).** The host also checks the build it installed and the moment it launched the runner, as a walk checks its manifest's `startedAt`: two dry runs of one walkbook to one path pass `requireFresh` together, and the one whose runner could not write would otherwise read the other's report — possibly of another build — as its own. That still misses overlapping runs of the *same* build: a second run launched before the first's runner starts probing can read the first's report, started after the second's own launch. The nonce closes that gap — generated fresh per dry run and echoed back by the runner, it is the one thing two overlapping runs of the same build cannot share.
public struct RouteProbeReport: Codable, Equatable, Sendable {
    /// The format this build writes.
    ///
    /// 2 added `startedAt` (SimWalk#36). 3 added `nonce` (SimWalk#36).
    public static let currentFormatVersion = 3

    /// The format this report is written in.
    public let formatVersion: Int
    /// The walkbook's name.
    public let walkName: String
    /// The app the routes were followed in.
    public let appBundleID: String
    /// The installed build the routes were followed against, as the host hashed it.
    public let appBuildHash: String
    /// The walkbook that was executed, from `WalkbookIdentity`.
    public let walkbookHash: String
    /// The commit the runner that wrote this was built from; `nil` when the host could not tell.
    public let runnerCommit: String?
    /// The device the routes were followed on.
    public let device: CaptureManifest.Device
    /// When the runner began following routes, by its own clock — what the host holds against the moment it launched the runner.
    public let startedAt: Date
    /// The value this run's host generated and passed the runner, echoed back — what tells this report from one an overlapping run of the same build left (SimWalk#36).
    public let nonce: String
    /// One entry per walkbook screen, in walkbook order.
    public let probes: [RouteProbe]

    public init(
        formatVersion: Int = RouteProbeReport.currentFormatVersion,
        walkName: String,
        appBundleID: String,
        appBuildHash: String,
        walkbookHash: String,
        runnerCommit: String?,
        device: CaptureManifest.Device,
        startedAt: Date,
        nonce: String,
        probes: [RouteProbe]
    ) {
        self.formatVersion = formatVersion
        self.walkName = walkName
        self.appBundleID = appBundleID
        self.appBuildHash = appBuildHash
        self.walkbookHash = walkbookHash
        self.runnerCommit = runnerCommit
        self.device = device
        // Rounded as a manifest's is, so a report read back equals the one written.
        self.startedAt = Timestamp.millisecondRounded(startedAt)
        self.nonce = nonce
        self.probes = probes
    }
}

public extension RouteProbeReport {
    /// The extension a probe file carries — what makes a dry run's output recognisable without opening it, and keeps it from being named like a capture bundle.
    static var fileExtension: String {
        "json"
    }

    /// Refuses an output path a dry run cannot honestly write to: one not named as a JSON file, or one that already exists.
    ///
    /// **Existing at all is a refusal, not an overwrite.** A report already at the path would otherwise be read back as this run's when the runner failed to write one — the stale-bundle hole `CaptureBundleWriter.requireFresh` closes for a walk, closed the same way: the caller removes it, because deleting a file this tool did not write is the wrong default for a tool pointed at arbitrary paths.
    static func requireFresh(_ url: URL, fileManager: FileManager = .default) throws {
        guard url.pathExtension == fileExtension else {
            throw RouteProbeError.misnamed(path: url.path, expectedExtension: fileExtension)
        }
        guard !fileManager.fileExists(atPath: url.path) else {
            throw RouteProbeError.alreadyExists(path: url.path)
        }
    }

    /// Writes the report to `url`, refusing one that does not describe `walkbook` and never replacing a file already there.
    func write(to url: URL, of walkbook: Walkbook) throws {
        let problems = try problems(against: walkbook)
        guard problems.isEmpty else {
            throw RouteProbeError.invalid(path: url.path, problems: problems)
        }
        do {
            try CaptureBundle.encoder().encode(self).write(to: url, options: .withoutOverwriting)
        } catch {
            throw RouteProbeError.notWritable(path: url.path, reason: error.localizedDescription)
        }
    }

    /// Reads the report at `url`, refusing one that does not describe `walkbook` — the walkbook the host handed the runner — or that is not this run's: followed against a build other than `buildHash`, started before `runnerLaunchedAt`, or carrying a nonce other than `nonce` — the one this run generated and passed its own runner, which catches what the other two miss: an overlapping run of the same build whose runner started after this one launched (SimWalk#36).
    ///
    /// A second's slack on the start, as `WalkCommand.bundleWrittenBy` allows a manifest: the report rounds to the millisecond and the runner's clock is the simulator's, not this process's.
    static func read(at url: URL, of walkbook: Walkbook, buildHash: String, runnerLaunchedAt: Date, nonce: String) throws -> RouteProbeReport {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RouteProbeError.missing(path: url.path, reason: error.localizedDescription)
        }
        // The version before the rest, as a manifest's is: a report of another format may lack a key this one
        // requires, and would otherwise be called torn rather than named by its format.
        let found: Int
        do {
            found = try JSONDecoder().decode(FormatEnvelope.self, from: data).formatVersion
        } catch {
            throw RouteProbeError.malformed(path: url.path, reason: "\(error)")
        }
        guard found == currentFormatVersion else {
            throw RouteProbeError.unsupportedFormatVersion(path: url.path, found: found, supported: currentFormatVersion)
        }
        let report: RouteProbeReport
        do {
            report = try CaptureBundle.decoder().decode(RouteProbeReport.self, from: data)
        } catch {
            throw RouteProbeError.malformed(path: url.path, reason: "\(error)")
        }
        let problems = try report.problems(against: walkbook)
        guard problems.isEmpty else {
            throw RouteProbeError.invalid(path: url.path, problems: problems)
        }
        var elsewhere: [String] = []
        if report.appBuildHash != buildHash {
            elsewhere.append("it was followed against build \(ShortHash.of(report.appBuildHash)), not \(ShortHash.of(buildHash)), the one this run installed")
        }
        if report.startedAt < runnerLaunchedAt.addingTimeInterval(-1) {
            elsewhere.append("it started at \(Timestamp.string(from: report.startedAt)), before this run launched its runner at \(Timestamp.string(from: runnerLaunchedAt))")
        }
        if report.nonce != nonce {
            elsewhere.append("it carries another run's nonce — an overlapping run of this build wrote it")
        }
        guard elsewhere.isEmpty else {
            throw RouteProbeError.fromAnotherRun(path: url.path, problems: elsewhere)
        }
        return report
    }

    /// Every way this report fails to describe a dry run of `walkbook` — all of them, not the first.
    func problems(against walkbook: Walkbook) throws -> [String] {
        var problems: [String] = []
        let expectedHash = try WalkbookIdentity.hash(of: walkbook)
        if walkbookHash != expectedHash {
            problems.append("it is of walkbook \(ShortHash.of(walkbookHash)), not \(ShortHash.of(expectedHash)), the one this run executed")
        }
        if appBundleID != walkbook.appBundleID {
            problems.append("it followed routes in \(appBundleID), where the walkbook names \(walkbook.appBundleID)")
        }
        let stated = probes.map(\.screenID)
        let expected = walkbook.screens.map(\.id)
        if stated != expected {
            problems.append("it probes [\(stated.joined(separator: ", "))], where the walkbook lists [\(expected.joined(separator: ", "))]")
        }
        for (probe, screen) in zip(probes, walkbook.screens) where probe.screenID == screen.id {
            // A landed `systemTap` carries its owner, which the walkbook never writes — compared as written.
            if probe.route.map(\.asWritten) != screen.route {
                problems.append("'\(probe.screenID)' carries the route \(probe.route.rendered), where the walkbook states \(screen.route.rendered)")
            }
            if let index = probe.failedStepIndex, !probe.route.indices.contains(index) {
                problems.append("'\(probe.screenID)' stops at step \(index + 1) of a \(probe.route.count)-step route")
            }
            // An owner is the runner's record of a step it took, so one on a step that never landed claims a tree nobody read.
            if let index = probe.route.indices.dropFirst(probe.resolvedSteps.count).first(where: { probe.route[$0] != probe.route[$0].asWritten }) {
                problems.append("'\(probe.screenID)' records where step \(index + 1) found its control, but that step never landed")
            }
        }
        return problems
    }

    /// The probes whose routes did not resolve — the screens a walk of this walkbook would not reach as written.
    var drifted: [RouteProbe] {
        probes.filter { !$0.isResolved }
    }
}

extension Walkbook.RouteStep {
    /// The step as a walkbook writes it: a `systemTap` without the owner the runner records on it, and with the `atLaunch` its author declared.
    ///
    /// The one spelling of that stripping, read by a dry run's check of its own report and by `session save`, which writes the landed steps a session took into a walkbook the loader would refuse with an owner in it.
    var asWritten: Walkbook.RouteStep {
        if case let .systemTap(label, atLaunch, .some) = self {
            return .systemTap(label: label, atLaunch: atLaunch)
        }
        return self
    }
}

private extension RouteProbeReport {
    /// The one field a reader asks for before the rest — `CaptureBundle`'s envelope, for the second artefact.
    struct FormatEnvelope: Decodable {
        var formatVersion: Int
    }
}
