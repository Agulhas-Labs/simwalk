//
// Copyright © Agulhas Labs
//

import Foundation

/// Merges the bundles of a `walk --parallel`'s shards into the one capture bundle a serial walk of the same screens would have written (SimWalk#163).
///
/// Each shard is an ordinary finalised bundle in its own scratch directory (`CaptureBundleLayout.shardScratchDirectory`) inside the output bundle's directory. The merge checks every shard before it moves anything, moves each shard's screen directories into the output by rename, and finalises through the same writer a serial walk does, so the merged bundle passes the same validation. The rules are recorded in the Brief ("walk --parallel: the merged bundle").
public struct ShardBundleMerge {
    /// Merges the shard bundles under `output`, one per shard in `plan`, into `output`'s own manifest and screen directories.
    ///
    /// `walkbook` is the book `plan` was made from — the narrowed one when `--screens` selected some — and its hash is the merged manifest's, as a serial walk of the same selection records.
    /// - Throws: ``ShardBundleMergeError`` when the shards were walked against different builds or one lacks a screen it was given; a `CaptureBundleError` when a shard does not read or the merged manifest does not validate.
    public static func merge(
        walkbook: Walkbook,
        plan: ShardPlan,
        into output: URL,
        fileManager: FileManager = .default
    ) throws -> Result {
        let shardURLs = plan.shards.indices.map { CaptureBundleLayout.shardScratchDirectory(in: output, index: $0) }
        let shards = try shardURLs.map { try CaptureBundle.read(at: $0, fileManager: fileManager) }
        let builds = Array(Set(shards.map(\.manifest.appBuildHash))).sorted()
        guard builds.count == 1 else { throw ShardBundleMergeError.buildsDiffer(builds: builds) }
        for (index, shard) in shards.enumerated() {
            let held = Set(shard.manifest.screens.map(\.id))
            if let missing = plan.shards[index].first(where: { !held.contains($0) }) {
                throw ShardBundleMergeError.screenMissing(shard: index, screenID: missing)
            }
        }

        // Every check has passed; from here the shards are consumed.
        var records: [String: CaptureManifest.ScreenRecord] = [:]
        for (index, shard) in shards.enumerated() {
            let device = shard.manifest.device
            for id in plan.shards[index] {
                guard var record = shard.manifest.screens.first(where: { $0.id == id }) else { continue }
                record.capturedOn = CaptureManifest.CapturingDevice(name: device.name, udid: device.udid)
                records[id] = record
                try moveScreenDirectory(id, from: shardURLs[index], to: output, fileManager: fileManager)
            }
        }
        let manifests = shards.map(\.manifest)
        let first = manifests[0]
        let order = walkbook.screens.map(\.id).filter { records[$0] != nil }
        var merged = try CaptureManifest(
            formatVersion: first.formatVersion,
            walkName: first.walkName,
            appBundleID: first.appBundleID,
            appBuildHash: first.appBuildHash,
            walkbookHash: WalkbookIdentity.hash(of: walkbook),
            device: first.device,
            startedAt: manifests.map(\.startedAt).min() ?? first.startedAt,
            finishedAt: manifests.map(\.finishedAt).max() ?? first.finishedAt,
            settleQuietMilliseconds: first.settleQuietMilliseconds,
            runnerCommit: first.runnerCommit,
            appearanceSettle: mergedSettle(manifests, walkbookOrder: order),
            nonce: first.nonce,
            appBuildProvenance: first.appBuildProvenance,
            animations: first.animations,
            screens: order.compactMap { records[$0] }
        )
        merged.deviceSetup = mergedSetup(manifests)
        let bundle = try CaptureBundleWriter(reopening: output, fileManager: fileManager).finalise(merged)

        var leftovers: [URL] = []
        for url in shardURLs {
            try? fileManager.removeItem(at: CaptureBundle.manifestURL(in: url))
            if holdsOnlyEmptyDirectories(url, fileManager: fileManager) {
                try fileManager.removeItem(at: url)
            } else {
                leftovers.append(url)
            }
        }
        return Result(bundle: bundle, leftoverShardDirectories: leftovers)
    }

    /// Renames one screen's directory out of a shard bundle into the output; a screen that captured nothing has no directory and moves nothing.
    private static func moveScreenDirectory(_ id: String, from shardURL: URL, to output: URL, fileManager: FileManager) throws {
        let relative = CaptureBundleLayout.screenDirectory(screenID: id)
        let source = CaptureBundleLayout.url(forRelativePath: relative, in: shardURL)
        guard fileManager.fileExists(atPath: source.path) else { return }
        let destination = CaptureBundleLayout.url(forRelativePath: relative, in: output)
        do {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            throw CaptureBundleError.notWritable(path: destination.path, reason: error.localizedDescription)
        }
    }

    /// Whether a directory holds no file at all — any depth of empty directories is nothing.
    private static func holdsOnlyEmptyDirectories(_ url: URL, fileManager: FileManager) -> Bool {
        guard let entries = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else { return false }
        for case let entry as URL in entries where (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true {
            return false
        }
        return true
    }

    /// The string, or `nil` when it is empty.
    private static func nonEmpty(_ text: String) -> String? {
        text.isEmpty ? nil : text
    }

    /// `udid`'s first eight characters, which tell devices apart in a line of prose.
    private static func shortID(_ device: CaptureManifest.Device) -> String {
        String(device.udid.prefix(8))
    }

    /// Each setup list concatenated in shard order, every entry saying which device made it.
    private static func mergedSetup(_ manifests: [CaptureManifest]) -> CaptureManifest.SetupRecord? {
        let setups = manifests.compactMap { manifest in manifest.deviceSetup.map { (manifest.device, $0) } }
        guard !setups.isEmpty else { return nil }
        func suffixed(_ list: (CaptureManifest.SetupRecord) -> [String]?) -> [String] {
            setups.flatMap { device, setup in (list(setup) ?? []).map { "\($0) (on \(shortID(device)))" } }
        }
        return CaptureManifest.SetupRecord(
            made: suffixed(\.made),
            statusBarNotReapplied: nonEmpty(suffixed { $0.statusBarNotReapplied.map { [$0] } }.joined(separator: "; ")),
            handedBack: suffixed(\.handedBack),
            unconfirmed: suffixed(\.handedBackUnconfirmed),
            notHandedBack: suffixed(\.notHandedBack),
            leftover: suffixed(\.leftover)
        )
    }

    /// The one settle as it is when a single shard made one; otherwise the shards' joined, with each failure naming its device.
    ///
    /// When any shard's settle did not fold, only the retries of those that did not are kept, because a settle that did not fold may only name screens whose records are their first attempts.
    private static func mergedSettle(_ manifests: [CaptureManifest], walkbookOrder: [String]) -> CaptureManifest.AppearanceSettle? {
        let settles = manifests.compactMap { manifest in manifest.appearanceSettle.map { (manifest.device, $0) } }
        guard let (_, head) = settles.first else { return nil }
        guard settles.count > 1 else { return head }
        func named(_ failure: (CaptureManifest.AppearanceSettle) -> String?) -> String? {
            nonEmpty(settles.compactMap { device, settle in failure(settle).map { "\(device.name) (\(shortID(device))): \($0)" } }
                .joined(separator: "; "))
        }
        // A settle that did not fold says every screen it retried kept its first attempt, and the validator holds the
        // whole record to that. A shard whose settle folded has second attempts in its records, so its retries cannot
        // sit in a settle that failed: they are left out, and the failure names the devices that did not fold.
        let anyUnfolded = settles.contains { !$0.1.folded }
        let retried = settles.filter { !anyUnfolded || !$0.1.folded }.flatMap(\.1.retried)
        let declined = settles.compactMap { device, settle in settle.declined.map { (device, $0) } }
        return CaptureManifest.AppearanceSettle(
            appearance: head.appearance,
            found: head.found,
            milliseconds: settles.reduce(0) { $0 + $1.1.milliseconds },
            retried: walkbookOrder.compactMap { id in retried.first { $0.id == id } },
            settleFailure: named(\.settleFailure),
            secondPassFailure: named(\.secondPassFailure),
            declined: declined.isEmpty ? nil : CaptureManifest.AppearanceSettle.Declined(
                reason: declined.map { "\($0.0.name) (\(shortID($0.0))): \($0.1.reason)" }.joined(separator: "; "),
                command: declined.map(\.1.command).joined(separator: "; ")
            )
        )
    }
}

public extension ShardBundleMerge {
    /// The merged bundle, and the shard directories that still hold something.
    struct Result {
        /// The merged bundle, as it reads back.
        public let bundle: CaptureBundle
        /// Shard directories kept because they hold more than empty directories once the merge has taken what it owns — named in the answer so nothing is lost silently.
        public let leftoverShardDirectories: [URL]
    }
}
