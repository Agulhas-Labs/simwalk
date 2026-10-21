//
// Copyright © Agulhas Labs
//

import CryptoKit
import Foundation
import SimWalkCore

/// Finds the XCUITest runner a walk builds, and says which commit it is.
///
/// The runner is built from source rather than shipped prebuilt (Brief §7.4). It used to be built from the checkout the binary was compiled in, found through `#filePath`, at whatever that checkout held at the moment of the walk — so an edit in progress there reached every walk on the machine, and a finished one paired the installed CLI with a runner from a different commit (SimWalk#16). An installed binary now builds only the snapshot `install-hook` paired it with.
///
/// Three sources, in order of how deliberate each one is, and a refusal naming what was looked for rather than a guess:
///
/// 1. `SIMWALK_RUNNER_PROJECT`, named explicitly.
/// 2. The checkout a development build lives in — a binary under `<checkout>/.build/`, which by construction was built from that working tree, edits and all. A packaged build has no checkout (`compiledCheckout` is `nil`), so it is never a development build and this route does not exist for it.
/// 3. The snapshot paired with this binary's SHA-256 in the `RunnerStore`. A packaged binary that has none yet — the first walk after `brew upgrade`, which swaps the binary and ships a new tree beside it without running `install-hook` — installs the tree shipped beside it (`ShippedRunner`), when that tree is stamped for this very binary, and walks with that. **Only the shipped tree**: a walk never snapshots a checkout (SimWalk#16), whose contents at the moment of the walk are exactly the skew the store exists to prevent.
public struct RunnerProject {
    /// The runner a walk from `executable` builds, or a refusal naming everywhere that was looked.
    ///
    /// - Parameters:
    ///   - environment: where the override is read from.
    ///   - executable: the running binary, which decides whether this is a development build inside its checkout.
    ///   - binaryHash: the running binary's SHA-256 as it was launched — asked only when a paired snapshot is needed.
    ///   - checkout: the checkout this binary was compiled from, or `nil` for a packaged build, which has none.
    ///   - store: where install-time snapshots are paired with binaries.
    ///   - run: spawns `git`, to name the commit of a checkout that is not a snapshot.
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        executable: URL?,
        binaryHash: () -> String?,
        checkout: URL? = compiledCheckout,
        store: RunnerStore = .standard(),
        run: (String, [String]) throws -> Shell.Result,
        fileManager: FileManager = .default
    ) throws -> RunnerSource {
        // 1. Told explicitly. An override that points at nothing is a mistake worth reporting rather than
        //    quietly falling through to a guess the caller did not ask for.
        if let override = environment[overrideVariable] {
            guard fileManager.fileExists(atPath: override) else {
                throw RunnerProjectError.overrideMissing(variable: overrideVariable, path: override)
            }
            let root = URL(fileURLWithPath: override).standardizedFileURL.deletingLastPathComponent().deletingLastPathComponent()
            return RunnerSource(projectPath: override, commit: commit(of: root, run: run), origin: .override)
        }

        // 2. A development build inside its own checkout: the binary and the runner are the same working tree.
        if let executable, let checkout, isInside(executable, buildDirectoryOf: checkout) {
            let checkoutProject = project(under: checkout.path)
            if fileManager.fileExists(atPath: checkoutProject) {
                return RunnerSource(projectPath: checkoutProject, commit: commit(of: checkout, run: run), origin: .checkout)
            }
        }

        // 3. The snapshot this binary was installed with — never the live checkout, whatever it holds.
        guard let hash = binaryHash() else {
            throw RunnerProjectError.binaryUnreadable(variable: overrideVariable)
        }
        var shippedReason: String?
        var found = store.binding(forBinary: hash)
        if found == nil {
            // An upgraded packaged binary has no binding yet, and the tree shipped beside it is its own runner.
            if let executable {
                do {
                    let shipped = try ShippedRunner.find(besideExecutable: executable, binaryHash: hash, fileManager: fileManager)
                    found = try store.install(shipped: shipped, binaryHash: hash).binding
                } catch let absence as ShippedRunner.Absence {
                    shippedReason = absence.description
                }
            } else {
                shippedReason = "the binary's own path is unknown, so no shipped runner tree could be looked for"
            }
        }
        guard let binding = found else {
            throw RunnerProjectError.notInstalled(binaryHash: hash, latest: store.latestBinding(), variable: overrideVariable, shipped: shippedReason, packaged: checkout == nil)
        }
        guard fileManager.fileExists(atPath: binding.projectPath) else {
            throw RunnerProjectError.snapshotMissing(path: binding.snapshot, commit: binding.commit, packaged: checkout == nil)
        }
        return RunnerSource(projectPath: binding.projectPath, commit: binding.commit, origin: .installed)
    }

    /// The environment variable that overrides every other route.
    public static var overrideVariable: String {
        "SIMWALK_RUNNER_PROJECT"
    }

    /// The checkout this binary was compiled from — `#filePath` is baked in at build time, so it names the source tree whatever the binary was copied to — or `nil` for a packaged build.
    ///
    /// **A release build passes `-Xswiftc -DSIMWALK_PACKAGED`, and then `#filePath` is not compiled at all.** swiftc's `-file-prefix-map` does not rewrite `#filePath`, so a shipped binary would otherwise carry the build machine's path; and a binary with no checkout is never a development build, so every route that needs one is closed to it rather than pointed at a directory that is not there.
    public static var compiledCheckout: URL? {
        #if SIMWALK_PACKAGED
        nil
        #else
        URL(fileURLWithPath: #filePath).standardizedFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        #endif
    }

    /// The SHA-256 of the executable at `url`, or `nil` when it cannot be read.
    public static func hash(ofExecutableAt url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var digest = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            digest.update(data: chunk)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The runner's Xcode project under a source tree.
    static func project(under root: String) -> String {
        URL(fileURLWithPath: root)
            .appendingPathComponent("Runner")
            .appendingPathComponent("SimWalkRunner.xcodeproj")
            .path
    }

    /// The commit a working tree is at — `<sha>`, or `<sha>-dirty` when `GitWorkingTree` finds anything but `HEAD` in it — or `nil` when it is not a git checkout.
    ///
    /// A checkout that is not a snapshot is built as it is on disk, so a clean `HEAD` is the only thing that describes it exactly; a dirty one is marked rather than passed off as its commit.
    static func commit(of root: URL, run: (String, [String]) throws -> Shell.Result) -> String? {
        guard let sha = try? GitWorkingTree.head(of: root, run: run), !sha.isEmpty else { return nil }
        let dirty = (try? GitWorkingTree.isDirty(root, run: run)) ?? true
        return dirty ? "\(sha)-dirty" : sha
    }

    /// Whether `executable` is a development build — a binary under `<checkout>/.build/`, which walks build from that working tree and whose SHA-256 changes with its next build.
    ///
    /// A prune refuses to run from one (SimWalk#22): the binding it would keep is gone at its next build, and the installs it would call old are judged by a binary nothing else is running.
    public static func isDevelopmentBuild(_ executable: URL, of checkout: URL) -> Bool {
        isInside(executable, buildDirectoryOf: checkout)
    }

    private static func isInside(_ executable: URL, buildDirectoryOf checkout: URL) -> Bool {
        let build = checkout.appendingPathComponent(".build").resolvingSymlinksInPath().standardizedFileURL.path + "/"
        return executable.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(build)
    }
}
