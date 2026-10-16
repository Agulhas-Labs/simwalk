//
// Copyright © Agulhas Labs
//

import Foundation

/// A capture bundle mid-walk — the directory exists, the manifest does not yet.
///
/// The two phases exist because a walk's outcomes are only knowable *after* it has run — a runner cannot hand over a finished manifest before it has tried to reach anything. So the executor opens a writer, asks for a directory as it arrives at each state, drops its screenshot and AX tree in, and calls `finalise` once with what actually happened.
///
/// **The manifest is written last, and that ordering is the whole guarantee.** A manifest asserting `captured [light, dark]` that landed *before* the artefacts would make an interrupted run inspect as a pass; written last, an interrupted run leaves a directory with no manifest, which `CaptureBundle.read` refuses by name. `finalise` additionally refuses a manifest whose claims the directory does not support, so a bundle cannot be created in a state that reading it would reject.
public struct CaptureBundleWriter {
    /// The bundle directory being written.
    public let url: URL
    private let fileManager: FileManager
    /// When each state's directory was prepared, keyed by screen id and state slug — the fallback capture time `finalise` stamps onto a record that arrives without its own read time.
    private let preparedAt = PreparedTimes()
    /// Where the capture time comes from: a parameter, never a naked `Date()` in the logic, so a test can state it.
    private let clock: @Sendable () -> Date

    /// Creates the bundle directory, ready for artefacts, and writes no manifest.
    ///
    /// **Refuses an existing directory that is not empty**, and refuses a directory it cannot list rather than reading the failure as emptiness. Writing into one would let a re-run validate on the *previous* run's artefacts — Friday's failed capture passing on Monday's file at the same path, which is the artefact check confirming a fact about the wrong walk. Refusing rather than clearing is deliberate: deleting files the tool did not just write is the wrong default for a tool pointed at arbitrary paths, and a stale bundle is the caller's to remove.
    ///
    /// Also refuses a path that is not named as a bundle, so nothing this tool writes is unrecognisable as its output.
    public init(preparingAt url: URL, fileManager: FileManager = .default, clock: @escaping @Sendable () -> Date = { Date() }) throws {
        self.url = url
        self.fileManager = fileManager
        self.clock = clock
        try Self.requireFresh(url, fileManager: fileManager)
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw CaptureBundleError.notWritable(path: url.path, reason: error.localizedDescription)
        }
    }

    /// A writer for a bundle directory that already holds its artefacts and has had its manifest taken away — the one caller is `AppearanceRetry.fold`, which swaps a retried screen's artefacts in and then finalises, so the manifest is still written last.
    ///
    /// Internal, so a runner cannot reach it: the fresh-directory refusal above is the rule for every walk, and this exists only for a fold that has already read both bundles and removed the manifest it is replacing.
    init(reopening url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
        clock = { Date() }
    }

    /// Refuses a path a fresh bundle cannot be written to — misnamed, or already holding something — without creating anything.
    ///
    /// The writer's own check, public so a walk can make it **before** it boots, builds or launches anything (the SimWalk#19 review). The runner makes the writer in another process, and a refusal there leaves the old bundle on disk for the host to read back as the walk it just ran — a stale bundle reported as this walk's result, down to a device check that reads `held`. Asked first, on the host, that path does not exist: a readable bundle after a walk can then only be the one the walk wrote.
    public static func requireFresh(_ url: URL, fileManager: FileManager = .default) throws {
        try CaptureBundleLayout.requireBundleName(url)
        if fileManager.fileExists(atPath: url.path) {
            let existing: [String]
            do {
                existing = try fileManager.contentsOfDirectory(atPath: url.path)
            } catch {
                // An unlistable directory is not an empty one. Reading the failure as emptiness — which
                // `try?` did — fails open on precisely the case the guard exists to catch: a stale bundle
                // whose contents this process cannot see, which `finalise` would then confirm for the
                // wrong walk.
                throw CaptureBundleError.notWritable(path: url.path, reason: error.localizedDescription)
            }
            guard existing.isEmpty else {
                throw CaptureBundleError.bundleDirectoryNotEmpty(path: url.path, entries: existing.count)
            }
        }
    }

    /// Creates and returns the directory one state's artefacts belong in.
    ///
    /// Called per state as its artefacts are about to be filed — never up front for the whole walkbook, so a screen that turned out to be unreachable, or whose states cannot all have applied, leaves no directory behind. An absent directory beside a stated refusal is a fact; an empty one would read as a capture that produced nothing.
    @discardableResult
    public func prepareDirectory(screenID: String, state: Walkbook.CaptureState) throws -> URL {
        let relative = CaptureBundleLayout.stateDirectory(screenID: screenID, stateSlug: state.slug)
        let directory = CaptureBundleLayout.url(forRelativePath: relative, in: url)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw CaptureBundleError.notWritable(path: directory.path, reason: error.localizedDescription)
        }
        preparedAt.record(clock(), for: relative)
        return directory
    }

    /// Validates the manifest against its own invariants and against what is on disk, then writes it — last.
    @discardableResult
    public func finalise(_ manifest: CaptureManifest) throws -> CaptureBundle {
        // A capture carries the time of its own read, and keeps it. Only one that arrives without one is
        // stamped with the moment its directory was prepared — which is when the screen's states were
        // filed, after the last of them was read, so it is a fallback and never the runner's answer
        // (Brief §8, the value oracle's core).
        let manifest = manifest.stampingCaptureTimes { screenID, slug in
            preparedAt.time(for: CaptureBundleLayout.stateDirectory(screenID: screenID, stateSlug: slug))
        }
        let manifestURL = CaptureBundle.manifestURL(in: url)
        let problems = CaptureManifestValidator.problems(in: manifest)
            + CaptureManifestValidator.missingArtefactProblems(for: manifest, in: url, fileManager: fileManager)
            + CaptureManifestValidator.identicalToProblems(for: manifest, in: url, fileManager: fileManager)
        guard problems.isEmpty else {
            throw CaptureBundleError.manifestInvalid(path: manifestURL.path, problems: problems)
        }
        do {
            try CaptureBundle.encoder().encode(manifest).write(to: manifestURL, options: .atomic)
        } catch {
            throw CaptureBundleError.notWritable(path: manifestURL.path, reason: error.localizedDescription)
        }
        return CaptureBundle(url: url, manifest: manifest)
    }
}

extension CaptureBundleWriter {
    /// The writer is a value handed around the runner, so the times it records live in one reference it shares with its copies.
    final class PreparedTimes: @unchecked Sendable {
        private let lock = NSLock()
        private var times: [String: Date] = [:]

        func record(_ time: Date, for directory: String) {
            lock.withLock { times[directory] = time }
        }

        func time(for directory: String) -> Date? {
            lock.withLock { times[directory] }
        }
    }
}
