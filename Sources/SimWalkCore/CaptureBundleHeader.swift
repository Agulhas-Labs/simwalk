//
// Copyright © Agulhas Labs
//

import Foundation

/// The line every answer about a capture bundle opens with: what the answer was measured against.
///
/// One generator for `inspect`, `walk` and `audit` alike, because they answer three questions about the same artefact and a reader comparing two of them is comparing the runs, not the renderings. Six facts, in the order a reader disambiguates by: the plan by name, the app it was run against, the binary of that app, the plan's content hash, the device, and how much of what came back was recorded after the accessibility tree had stopped moving.
///
/// **The name and the app id are load-bearing, not decoration.** They were briefly dropped as provenance, which left two bundles of different apps answering identically but for a hash nobody can read as a name — the compression had gone one field too far. A hash tells two runs apart; it does not tell a reader *what they are looking at*, and the header's job is both. The walk name lives here rather than in the verdict, and `validate` puts its walkbook's name in the same position, so one rule covers every face.
///
/// **Not the timestamps and not the UDID.** Those are the two that did leave, on the contract's wording rule: dates and machine names never appear in an answer, and a hash is the only provenance. A bundle read on another machine a week later is the normal case, and a reader who anchors on "ran at 06:56" has anchored on nothing. Both are still in the manifest, which is the record; this is the answer.
public struct CaptureBundleHeader {
    /// The header for `bundle`: ``line(_:)-swift.type.method`` of its manifest, then the note on how its path was reached when there is one (SimWalk#107), so every bundle command says it once in the same place.
    public static func line(of bundle: CaptureBundle) -> String {
        [line(bundle.manifest), bundle.pathNote].compactMap(\.self).joined(separator: "  ")
    }

    /// The header for the walk `manifest` describes.
    ///
    /// The runner that wrote the bundle is named beside the build and the walkbook when the manifest records it (SimWalk#16) — the third identity a bundle carries — and left out of a bundle written before it did, rather than printed as unknown.
    public static func line(_ manifest: CaptureManifest) -> String {
        [
            "walk: '\(manifest.walkName)'",
            "app: \(manifest.appBundleID)",
            "build: \(AppBuildIdentity.printed(manifest.appBuildHash))",
            "walkbook: \(ShortHash.of(manifest.walkbookHash))",
            manifest.runnerCommit.map { "runner: \(ShortHash.of($0))\($0.contains("-dirty") ? "-dirty" : "")" },
            "device: \(manifest.device.name) (\(manifest.device.osVersion))",
            "settled: \(settled(manifest))",
        ].compactMap(\.self).joined(separator: "  ")
    }

    /// How many of the bundle's captures were taken after the accessibility tree held still — a declared gap where a bundle never recorded it, never a guess either way.
    ///
    /// A bundle written before the runner recorded settling says `unrecorded` rather than `0/3`, which would report a gap in the record as a fault in the walk. A bundle that records it for some captures and not others says both figures, for the same reason: the unrecorded ones are neither settled nor unsettled, and folding them into either number is the silent under-report the contract's sixth rule is about.
    private static func settled(_ manifest: CaptureManifest) -> String {
        let captures = manifest.screens.flatMap(\.captures)
        guard !captures.isEmpty else { return "no captures" }
        let unrecorded = captures.filter { $0.axTreeSettled == nil }.count
        guard unrecorded < captures.count else { return "unrecorded" }
        let settled = captures.filter { $0.axTreeSettled == true }.count
        let counted = "\(settled)/\(captures.count)"
        return unrecorded == 0 ? counted : "\(counted) (\(unrecorded) unrecorded)"
    }
}
