//
// Copyright © Agulhas Labs
//

import Foundation

/// A finished capture bundle on disk: the manifest, and the directory its artefacts live in.
///
/// This type is the read side of the runner boundary (Brief §5); `CaptureBundleWriter` is the write side. The differ and the oracle call `read` and get a manifest they can trust or a refusal that says why — and "can trust" is load-bearing, because reading verifies that every capture the manifest claims is actually in the directory. Neither side derives a path; both ask `CaptureBundleLayout`.
public struct CaptureBundle: Equatable, Sendable {
    /// The bundle directory.
    public let url: URL
    /// The manifest read from, or written to, that directory.
    public let manifest: CaptureManifest
    /// How the path was reached, when the caller's lacked `.simwalk` and this tool added it (SimWalk#107).
    ///
    /// A fact about the path rather than the bundle, carried so ``CaptureBundleHeader`` says it once on every answer; `nil` when the path was used as given.
    public private(set) var pathNote: String?

    public init(url: URL, manifest: CaptureManifest) {
        self.url = url
        self.manifest = manifest
    }

    /// This bundle with `note` riding its answers' header.
    public func noting(_ note: String) -> CaptureBundle {
        var copy = self
        copy.pathNote = note
        return copy
    }

    /// Reads the bundle at `url` — or at `<url>.simwalk` when `url` is unnamed, absent, and that sibling exists (SimWalk#107), noted on the bundle for the header — refusing, never defaulting, when it is not named as a bundle, is not a bundle, its manifest is absent, torn, of an unknown format, self-contradictory, or claims artefacts the directory does not hold.
    public static func read(at asked: URL, fileManager: FileManager = .default) throws -> CaptureBundle {
        let resolution = CaptureBundleLayout.resolvingForRead(asked, fileManager: fileManager)
        let url = resolution.url
        try CaptureBundleLayout.requireBundleName(url)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CaptureBundleError.notABundle(path: url.path)
        }
        let manifestURL = manifestURL(in: url)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw CaptureBundleError.manifestMissing(bundlePath: url.path, expectedPath: manifestURL.path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            throw CaptureBundleError.manifestUnreadable(path: manifestURL.path, reason: error.localizedDescription)
        }
        try requireReadableFormat(of: data, at: manifestURL.path)
        let manifest: CaptureManifest
        do {
            manifest = try decoder().decode(CaptureManifest.self, from: data)
        } catch {
            throw CaptureBundleError.manifestMalformed(path: manifestURL.path, reason: DecodingReason.sentence(for: error))
        }
        let problems = CaptureManifestValidator.problems(in: manifest)
            + CaptureManifestValidator.missingArtefactProblems(for: manifest, in: url, fileManager: fileManager)
            + CaptureManifestValidator.identicalToProblems(for: manifest, in: url, fileManager: fileManager)
        guard problems.isEmpty else {
            throw CaptureBundleError.manifestInvalid(path: manifestURL.path, problems: problems)
        }
        let bundle = CaptureBundle(url: url, manifest: manifest)
        return resolution.suffixAdded ? bundle.noting("(read \(url.lastPathComponent): suffix added)") : bundle
    }

    /// Refuses manifest bytes whose declared format is not one `readable` names, by name — before anything else in them is decoded.
    ///
    /// The version is read before the manifest, not after it. Every incompatible change is by definition one this build's shape does not decode, so asking the decoded manifest for its version made the only refusal `formatVersion` exists to produce unreachable: a format-2 manifest that renamed a required key failed the full decode first and was reported as torn. `readable` is a parameter so a test can hold an older build's list against what this one writes — the only way to check a bump was taken without running the older build.
    static func requireReadableFormat(of data: Data, at path: String, readable: [Int] = CaptureManifest.readableFormatVersions) throws {
        let declaredVersion: Int
        do {
            declaredVersion = try decoder().decode(FormatEnvelope.self, from: data).formatVersion
        } catch {
            throw CaptureBundleError.manifestMalformed(path: path, reason: DecodingReason.sentence(for: error))
        }
        guard readable.contains(declaredVersion) else {
            throw CaptureBundleError.unsupportedFormatVersion(path: path, found: declaredVersion, supported: readable)
        }
    }

    /// The manifest's location inside a bundle directory.
    public static func manifestURL(in bundleURL: URL) -> URL {
        bundleURL.appendingPathComponent(CaptureBundleLayout.manifestFileName)
    }

    /// The absolute location of a capture's screenshot inside this bundle.
    public func screenshotURL(for capture: CaptureManifest.StateCapture) -> URL {
        CaptureBundleLayout.url(forRelativePath: capture.screenshotPath, in: url)
    }

    /// The absolute location of a capture's accessibility tree inside this bundle.
    public func axTreeURL(for capture: CaptureManifest.StateCapture) -> URL {
        CaptureBundleLayout.url(forRelativePath: capture.axTreePath, in: url)
    }

    /// The accessibility tree recorded for one capture, decoded.
    ///
    /// Read on demand rather than held on the bundle: a walk of a dozen screens in three states carries several megabytes of tree, and every reader so far wants one screen at a time.
    ///
    /// **Refuses by name.** A tree this build cannot decode used to surface as Foundation's own `keyNotFound 'type'` — no bundle, no screen, no path, thrown out of whichever verb happened to ask — which is how a format-1 bundle came to fail `bundle audit` with a sentence naming nothing while `bundle inspect` on the same bundle printed cleanly. Every failure here names the artefact, and a format-1 bundle is told what it actually is rather than left to look corrupt.
    public func axTree(for capture: CaptureManifest.StateCapture) throws -> AXNode {
        let url = axTreeURL(for: capture)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CaptureBundleError.artefactUnreadable(path: url.path, reason: error.localizedDescription)
        }
        do {
            return try Self.decoder().decode(AXNode.self, from: data)
        } catch {
            let note = formatNote(for: error, in: data)
            let reason = DecodingReason.sentence(for: error) + note
            // An older bundle's tree is the caller's file to re-walk, not something the runner just wrote wrongly.
            throw note.isEmpty
                ? CaptureBundleError.artefactUnreadable(path: url.path, reason: reason)
                : CaptureBundleError.artefactFromOlderFormat(path: url.path, reason: reason)
        }
    }

    /// What to add to an artefact refusal when the bundle's own format explains it.
    ///
    /// **Judged against the format that introduced the typed tree, not against the current one.** Once the current version moved past 2 for a reason that has nothing to do with trees, `< currentFormatVersion` would have started offering a format-2 bundle — whose trees *are* typed — the note about the untyped dump, which is the confident-wrong-cause this note exists to avoid, one version later.
    ///
    /// **Conditioned on the evidence in hand, not on the version integer.** Format 1 spans both tree shapes — the version was bumped after the typed tree shipped, so 6 of the 15 bundles on this machine are format 1 carrying trees that decode today. Blaming the format for any failure in any of them would tell a reader whose file is truncated to re-walk a bundle whose problem is a damaged file, which is the confident-wrong-cause failure this note exists to prevent. Every real format-1 tree was written as `["raw": debugDescription]`, so the top-level `raw` key check alone covers the entire real population; a root-level tree missing `type` is damage to a *typed* tree, not evidence of the old format, so blaming the format there is exactly the confident-wrong-cause this note exists to avoid.
    private func formatNote(for _: Error, in data: Data) -> String {
        guard manifest.formatVersion < CaptureManifest.typedTreeFormatVersion else { return "" }
        guard Self.carriesUntypedDump(data) else { return "" }
        return " — this bundle is format \(manifest.formatVersion), whose accessibility trees are the untyped {\"raw\": …} dump that format \(CaptureManifest.typedTreeFormatVersion) replaced with a typed tree; walk it again to read it"
    }

    /// Whether the bytes read are the untyped `{"raw": …}` dump, judged by a top-level `raw` key.
    private static func carriesUntypedDump(_ data: Data) -> Bool {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return object.keys.contains("raw")
    }

    /// The encoder every writer uses: fractional-second timestamps and sorted keys, so two bundles of the same walk diff line by line.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Timestamp.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// The matching decoder — paired with `encoder()` here rather than at each call site, because a date strategy that disagrees across the boundary either fails as a malformed manifest or, worse, silently rounds the timestamps it read.
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = Timestamp.date(from: text) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "'\(text)' is not an ISO-8601 UTC timestamp (expected 2026-08-16T08:00:00.125Z, or the same without milliseconds)"
                    )
                )
            }
            return date
        }
        return decoder
    }
}

private extension CaptureBundle {
    /// The one field a reader asks for before it knows whether it can read the rest.
    ///
    /// Asking for nothing else is the whole point: a manifest of a format this build does not know may legitimately carry keys it has never heard of and be missing keys it requires, and it still has to be able to say which format it is.
    struct FormatEnvelope: Decodable {
        var formatVersion: Int
    }
}
