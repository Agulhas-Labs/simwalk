//
// Copyright © Agulhas Labs
//

import Foundation

/// The on-disk shape of a capture bundle, and the only place that shape is spelled.
///
/// A bundle is the contract on both sides of the runner boundary (Brief §5): the XCUITest executor writes it from inside the test process, and the differ and oracle read it back from a plain directory. Neither can be allowed to derive a path its own way, so every path in a bundle — the manifest's relative entries included — comes from here.
///
/// ```
/// walk.simwalk/
///   manifest.json
///   screens/
///     today/
///       light/
///         screen.png
///         ax-tree.json
///       dark/
///         …
/// ```
///
/// Screens that were never captured — an unreachable screen, or a build-mismatch refusal — have a manifest entry and no directory. That asymmetry is the point: the bundle records what happened, and an absent directory beside a stated refusal is a fact, where an empty directory would read as a capture that produced nothing.
public struct CaptureBundleLayout {
    /// The directory-extension a bundle carries, so a walk's output is recognisable without opening it.
    public static var directoryExtension: String {
        "simwalk"
    }

    /// Whether a path is named as a capture bundle.
    public static func isBundleName(_ url: URL) -> Bool {
        url.pathExtension == directoryExtension
    }

    /// Refuses a path that is not named as a bundle.
    ///
    /// Checked on both sides — a writer may not produce an unrecognisable directory, and a reader may not adopt one — because "recognisable without opening it" is a claim about every bundle in existence, and a property nothing enforces is a property some bundle will not have. It is also the difference between `simwalk bundle inspect ~/Downloads` answering "there is no manifest here" and answering the question actually asked.
    ///
    /// The rule still holds for every bundle on disk. What changed (SimWalk#107) is that a caller who left the suffix off is no longer refused when the right name is unambiguous: ``resolvingOutput(_:fileManager:)`` and ``resolvingForRead(_:fileManager:)`` add the suffix — never drop it, never rename anything — and say so in the answer.
    public static func requireBundleName(_ url: URL) throws {
        guard isBundleName(url) else {
            throw CaptureBundleError.misnamedBundle(path: url.path, expectedExtension: directoryExtension)
        }
    }

    /// Where a writer puts a bundle asked for at `url`: `url` itself when it is named as a bundle, `<url>.simwalk` when it is not and nothing exists at `url`, and `url` unchanged when something does.
    ///
    /// An unnamed path that already exists is left alone so the writer's refusal still fires — that is the case the naming rule protects, a directory somebody else made that a walk would otherwise adopt (SimWalk#107). A path with a different extension (`band8.bundle`) gets the suffix appended whole (`band8.bundle.simwalk`) rather than swapped, so what the caller typed stays recognisable.
    public static func resolvingOutput(_ url: URL, fileManager: FileManager = .default) -> Resolution {
        guard !isBundleName(url), !fileManager.fileExists(atPath: url.path) else {
            return Resolution(url: url, suffixAdded: false)
        }
        return Resolution(url: url.appendingPathExtension(directoryExtension), suffixAdded: true)
    }

    /// Where a reader finds a bundle asked for at `url`: `<url>.simwalk` when `url` is not named as a bundle, nothing exists at `url`, and the suffixed path does; otherwise `url` unchanged, so every other misnamed path is refused as before (SimWalk#107).
    ///
    /// The pair of ``resolvingOutput(_:fileManager:)``: a caller who wrote `--output x` was told `x.simwalk`, and the next command in the chain says `x`.
    public static func resolvingForRead(_ url: URL, fileManager: FileManager = .default) -> Resolution {
        let suffixed = url.appendingPathExtension(directoryExtension)
        guard !isBundleName(url), !fileManager.fileExists(atPath: url.path), fileManager.fileExists(atPath: suffixed.path) else {
            return Resolution(url: url, suffixAdded: false)
        }
        return Resolution(url: suffixed, suffixAdded: true)
    }

    /// The manifest's filename at the root of the bundle.
    public static var manifestFileName: String {
        "manifest.json"
    }

    /// The screenshot filename inside a state's directory — one image per state, of the viewport the tree is rooted at (full-scroll stitching is unbuilt).
    public static var screenshotFileName: String {
        "screen.png"
    }

    /// The accessibility-tree filename inside a state's directory — elements with their text runs and frames.
    public static var axTreeFileName: String {
        "ax-tree.json"
    }

    /// Apple's accessibility audit of one state, inside its directory — present only for a state a walk audited (`AppleAuditOptIn`).
    public static var appleAuditFileName: String {
        "apple-audit.json"
    }

    private static var screensDirectoryName: String {
        "screens"
    }

    /// Where an appearance retry's second pass writes its scratch bundle: inside the first attempt's own bundle, named as a bundle so the second runner's writer takes it (SimWalk#26).
    ///
    /// **Inside, so every move a fold makes is a rename** (the round-3 review). A fold moves the first attempt's manifest and screen directories aside and the second attempt's in. Between two volumes a move is a copy and then a delete, and one that fails between the two leaves a directory half in each place — which a scratch bundle under `$TMPDIR` and an `--output` on another volume made possible. A bundle's own folder is on the bundle's volume, and it is where a person looks: a fold stopped by force leaves the first attempt set aside inside the bundle it came from, not in a temporary directory the system purges on a timer.
    ///
    /// **A reader never sees it**: a bundle is read, sized and validated through the paths its manifest claims, and the manifest names nothing here. `id` keeps two scratch bundles apart; a walk makes one.
    public static func retryScratchDirectory(in bundleURL: URL, id: UUID) -> URL {
        bundleURL.appendingPathComponent(retryScratchDirectoryPrefix + id.uuidString).appendingPathExtension(directoryExtension)
    }

    private static var retryScratchDirectoryPrefix: String {
        "simwalk-retry-"
    }

    /// Where, inside an appearance retry's scratch bundle (`retryScratchDirectory`), a fold sets aside what it replaces in the first attempt — its manifest and each screen directory the second attempt takes over — so a fold that fails can put every one of them back (SimWalk#26).
    ///
    /// **Named as a bundle and laid out as one**: the manifest at its root, each screen directory at its usual path. A fold stopped by force — the process killed mid-swap — leaves the first attempt's pieces in a shape a person recognises and can move back, where deleting them would have left nothing to recover.
    public static func setAsideDirectory(in scratchBundleURL: URL) -> URL {
        scratchBundleURL.appendingPathComponent(setAsideDirectoryName).appendingPathExtension(directoryExtension)
    }

    private static var setAsideDirectoryName: String {
        "first-attempt"
    }

    /// Where a `walk --parallel` shard's own bundle is written: inside the merged bundle's directory, named as a bundle so the shard's runner writer takes it (SimWalk#163).
    ///
    /// **Inside, so every move the merge makes is a rename** — the same volume as the bundle it fills. **A reader never sees it**: the merged manifest names nothing here, and the merge removes the directory once it holds nothing but empty directories.
    public static func shardScratchDirectory(in bundleURL: URL, index: Int) -> URL {
        bundleURL.appendingPathComponent("\(shardScratchDirectoryPrefix)\(index)").appendingPathExtension(directoryExtension)
    }

    private static var shardScratchDirectoryPrefix: String {
        "simwalk-shard-"
    }

    /// Reduces one authored component to lowercase alphanumerics and underscores.
    ///
    /// This is the single place a caller-supplied string becomes a path component. A screen id and a capture state are both authored freely in a walkbook, so neither may be able to introduce a path separator, climb out of the bundle with `..`, or differ only by case — which two directories on a case-insensitive filesystem cannot.
    ///
    /// **The result is never empty**, because an empty component does not survive `url(forRelativePath:in:)` — it splits on `/` and drops it. A blank screen id would derive `screens//light/screen.png` and resolve to `screens/light/screen.png`, losing the screen level entirely and leaving a *state* slug standing where a screen belongs. The validators refuse a blank id; this makes the layout unable to produce a degenerate path even if one reaches it.
    public static func slugSegment(_ raw: String) -> String {
        let reduced = String(raw.lowercased().map { character in
            character.isLetter || character.isNumber ? character : "_"
        })
        return reduced.isEmpty ? "_" : reduced
    }

    /// The filename-safe identity a screen has on disk, derived from its walkbook id.
    ///
    /// Two ids reducing to the same slug are the same directory, which is why `WalkbookLoader` reports them as a collision rather than letting one screen's captures overwrite another's.
    public static func screenSlug(_ screenID: String) -> String {
        slugSegment(screenID)
    }

    /// The bundle-relative directory a screen's states are filed under, keyed by the screen's slug rather than its authored id.
    public static func screenDirectory(screenID: String) -> String {
        "\(screensDirectoryName)/\(screenSlug(screenID))"
    }

    /// The bundle-relative directory one captured state's artefacts are filed under.
    public static func stateDirectory(screenID: String, stateSlug: String) -> String {
        "\(screenDirectory(screenID: screenID))/\(stateSlug)"
    }

    /// The screen and state whose directory `path` is: the exact inverse of `stateDirectory(screenID:stateSlug:)`, so `nil` for any path that function cannot derive.
    ///
    /// The screen comes back as its slug, the only form of its id on disk. It is how a bundle whose manifest was never finalised names its captures: by their directories alone (SimWalk#190).
    public static func state(atStateDirectory path: String) -> (screenSlug: String, stateSlug: String)? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count == 3, components[0] == screensDirectoryName, !components[2].isEmpty else { return nil }
        let state = (screenSlug: components[1], stateSlug: components[2])
        return stateDirectory(screenID: state.screenSlug, stateSlug: state.stateSlug) == path ? state : nil
    }

    /// Every state under `bundleURL` whose directory holds an Apple audit record, in path order, read from the directories with no manifest.
    ///
    /// **A bundle whose manifest was never finalised still holds its audits' records** (SimWalk#190): the runner files each beside its capture and the manifest last, so a runner stopped or crashed after an audit leaves the records and nothing that lists them. A directory the layout cannot derive is not a state and is left out.
    public static func appleAuditStates(in bundleURL: URL, fileManager: FileManager = .default) -> [(screenSlug: String, stateSlug: String)] {
        let screens = (try? fileManager.contentsOfDirectory(atPath: url(forRelativePath: screensDirectoryName, in: bundleURL).path)) ?? []
        let directories = screens.flatMap { screen in
            let screenPath = "\(screensDirectoryName)/\(screen)"
            let states = (try? fileManager.contentsOfDirectory(atPath: url(forRelativePath: screenPath, in: bundleURL).path)) ?? []
            return states.map { "\(screenPath)/\($0)" }
        }
        return directories.sorted().compactMap { directory in
            state(atStateDirectory: directory).flatMap { state in
                fileManager.fileExists(atPath: url(forRelativePath: appleAuditPath(screenID: state.screenSlug, stateSlug: state.stateSlug), in: bundleURL).path) ? state : nil
            }
        }
    }

    /// The bundle-relative path of one state's screenshot.
    public static func screenshotPath(screenID: String, stateSlug: String) -> String {
        "\(stateDirectory(screenID: screenID, stateSlug: stateSlug))/\(screenshotFileName)"
    }

    /// The bundle-relative path of one state's accessibility tree.
    public static func axTreePath(screenID: String, stateSlug: String) -> String {
        "\(stateDirectory(screenID: screenID, stateSlug: stateSlug))/\(axTreeFileName)"
    }

    /// The bundle-relative path of one state's Apple accessibility audit record.
    public static func appleAuditPath(screenID: String, stateSlug: String) -> String {
        "\(stateDirectory(screenID: screenID, stateSlug: stateSlug))/\(appleAuditFileName)"
    }

    /// Resolves a bundle-relative path against the bundle's own directory.
    public static func url(forRelativePath path: String, in bundleURL: URL) -> URL {
        path.split(separator: "/").reduce(bundleURL) { url, component in
            url.appendingPathComponent(String(component))
        }
    }
}

public extension CaptureBundleLayout {
    /// A path after the suffix rule has been applied to it, and whether the suffix was the rule's doing (SimWalk#107).
    struct Resolution: Equatable {
        public let url: URL
        public let suffixAdded: Bool

        public init(url: URL, suffixAdded: Bool) {
            self.url = url
            self.suffixAdded = suffixAdded
        }
    }
}
