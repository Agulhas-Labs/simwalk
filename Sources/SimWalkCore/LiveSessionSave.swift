//
// Copyright © Agulhas Labs
//

import Foundation

/// `simwalk session save`: what a live session did, written as a walkbook screen a walk replays.
///
/// **The route is the landed steps, read from the session's responses** (``LiveSessionChannel/landedSteps(since:)``) and written as a walkbook writes them — a `systemTap` without the owner the runner records on it, which the loader refuses. **The state is the one the session launched under** (`launch.json`), or, when it launched plain, the appearance the device was found in, because a walkbook screen names its states and never captures "whatever the device is in".
///
/// **A range with a gap in its numbering is refused, naming each missing number** (``LiveSessionChannel/unfiledRequests(since:)``): on a device the runner answered that request and this Mac never filed it, so the route may lack a step it took. A simulator's numbering has no gaps, so the check never refuses one.
///
/// **Nothing is written that the loader would refuse.** The walkbook — new, or the one at `--into` with the screen appended — is encoded, then loaded back through ``WalkbookLoader`` from those very bytes, and only bytes that load are written, atomically. An existing walkbook is decoded and re-encoded whole, so its own layout and key order are not kept; the answer says so.
///
/// **Load, append and write are one step under an ``ExclusiveFileLock``** on the walkbook's directory (``lockFile(for:)``). The atomic write keeps a reader from seeing a torn file, not a writer from losing an update: two saves into one walkbook that both loaded it before either wrote would each write back only their own screen. Locking the directory leaves nothing in it; a lock file there would be litter in the repository the walkbook lives in.
///
/// **Symlinks are followed before anything is locked, loaded or written**, so every name for one walkbook locks and writes one file: a walkbook reached through a symlinked file or directory is saved into its target, and a link stays a link rather than being replaced by the atomic write.
public struct LiveSessionSave {
    public let screenID: String
    public let expect: String?
    /// The first request whose step is saved; `nil` saves every step since launch.
    public let since: Int?
    /// Follows a walkbook path's symlinks: ``resolved(_:)``, and the seam a test retargets a link through between two looks.
    var resolve: (URL) throws -> URL = Self.resolved

    public init(screenID: String, expect: String?, since: Int?) {
        self.screenID = screenID
        self.expect = expect
        self.since = since
    }

    /// Saves session `sessionID`'s route into the walkbook at `url`, creating it when it does not exist, and answers what was saved and how to replay it.
    ///
    /// - Parameter foundAppearance: the appearance `session start` found the device in, the state a session launched plain is saved under.
    public func perform(sessionID: String, channel: LiveSessionChannel, foundAppearance: Walkbook.Theme?, into url: URL) throws -> Answer {
        guard let launch = try channel.launch() else {
            throw LiveSessionSaveError.noLaunchRecord(path: channel.layout.launch.path)
        }
        let unfiled = channel.unfiledRequests(since: since ?? 1)
        guard unfiled.isEmpty else {
            throw LiveSessionSaveError.unfiledRequests(unfiled)
        }
        let landed = try channel.landedSteps(since: since ?? 1)
        let unlanded = try channel.unlandedSteps(since: since ?? 1)
        let screen = try screen(route: landed.map(\.step), launch: launch, foundAppearance: foundAppearance)
        let existing: Walkbook?
        // Resolved once: the lock and the write both take this one answer, so a link retargeted meanwhile cannot put them in different places.
        let target = try resolve(url)
        do {
            existing = try ExclusiveFileLock(file: target.deletingLastPathComponent()).withLock {
                let existing = FileManager.default.fileExists(atPath: target.path) ? try WalkbookLoader.load(contentsOf: target) : nil
                try Self.write(walkbook(adding: screen, app: launch.appBundleID, to: existing, path: url.path), to: target)
                return existing
            }
        } catch let unavailable as ExclusiveFileLock.Unavailable {
            // The lock is the walkbook's own directory, so one that cannot be opened is one the walkbook cannot be written into — said of the file the caller named.
            throw LiveSessionSaveError.notWritable(path: url.path, reason: unavailable.reason)
        }
        return answer(sessionID: sessionID, screen: screen, requests: (landed, unlanded), launch: launch, existing: existing, path: url.path)
    }

    /// The screen: `route` as a walkbook writes it, captured in the state the session launched under — or, launched plain, in the appearance the device was found in.
    func screen(route: [Walkbook.RouteStep], launch: LiveSessionLaunch, foundAppearance: Walkbook.Theme?) throws -> Walkbook.Screen {
        guard !route.isEmpty else {
            throw LiveSessionSaveError.nothingLanded(since: since)
        }
        guard let state = launch.state ?? foundAppearance.map({ Walkbook.CaptureState(theme: $0) }) else {
            throw LiveSessionSaveError.noState
        }
        return Walkbook.Screen(id: screenID, route: route.map(\.asWritten), states: [state], expect: expect)
    }

    /// `screen` appended to `existing`, or a new walkbook named for the screen when there is none — refusing a walkbook for another app, or one that already has the id.
    func walkbook(adding screen: Walkbook.Screen, app: String, to existing: Walkbook?, path: String) throws -> Walkbook {
        guard var walkbook = existing else {
            return Walkbook(name: screen.id, appBundleID: app, screens: [screen])
        }
        guard walkbook.appBundleID == app else {
            throw LiveSessionSaveError.differentApp(path: path, walkbook: walkbook.appBundleID, session: app)
        }
        guard !walkbook.screens.contains(where: { $0.id == screen.id }) else {
            throw LiveSessionSaveError.screenExists(path: path, id: screen.id)
        }
        walkbook.screens.append(screen)
        return walkbook
    }

    /// Encodes `walkbook`, loads the bytes back through the loader — so what is written is what a walk will accept — and writes them atomically.
    static func write(_ walkbook: Walkbook, to url: URL) throws {
        let data = try encoded(walkbook)
        _ = try WalkbookLoader.load(from: data, source: url.path)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw LiveSessionSaveError.notWritable(path: url.path, reason: error.localizedDescription)
        }
    }

    /// What a save into `url` locks: the directory its walkbook really lives in, symlinks followed, so two saves into one walkbook lock one directory whatever name each was given.
    static func lockFile(for url: URL) throws -> URL {
        try resolved(url).deletingLastPathComponent()
    }

    /// `url` with its symlinks followed: its directory's, and its own — a link to a walkbook not yet written included, which is followed to where the walkbook will be.
    ///
    /// `resolvingSymlinksInPath` follows neither for a walkbook not yet written, and not a dangling link at all: it answers the link itself, which the atomic write would then replace with a file. So the last component is read as a link here, a relative target taken from the link's directory, for as many hops as the kernel itself would follow.
    static func resolved(_ url: URL) throws -> URL {
        var current = url
        for _ in 0 ... maxSymlinkHops {
            let directory = current.deletingLastPathComponent().resolvingSymlinksInPath()
            let file = directory.appendingPathComponent(current.lastPathComponent)
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: file.path) else {
                return file
            }
            current = destination.hasPrefix("/") ? URL(fileURLWithPath: destination) : directory.appendingPathComponent(destination)
        }
        throw LiveSessionSaveError.notWritable(path: url.path, reason: "following its symlinks took more than \(maxSymlinkHops) hops — they loop, or chain deeper than the system follows")
    }

    /// The hops `resolved(_:)` follows before refusing: Darwin's `MAXSYMLINKS`, past which `open` itself answers `ELOOP`.
    static let maxSymlinkHops = 32

    /// A walkbook as this writes one: pretty-printed, keys sorted, slashes left alone.
    static func encoded(_ walkbook: Walkbook) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(walkbook) + Data("\n".utf8)
    }

    /// - Parameter requests: the steps that landed, which are the route, and the step requests that did not, which qualify it.
    private func answer(sessionID: String, screen: Walkbook.Screen, requests: (landed: [LiveSessionChannel.LandedStep], unlanded: [LiveSessionRequest]), launch: LiveSessionLaunch, existing: Walkbook?, path: String) -> Answer {
        let (landed, unlanded) = requests
        let steps = "\(landed.count) step\(landed.count == 1 ? "" : "s")"
        let requests = landed.map { String($0.request) }.joined(separator: ", ")
        let stateSource = launch.state == nil ? "the appearance the device was found in; the session launched with no state" : "the state the session launched under"
        var residue = [
            "route: \(screen.route.rendered)",
            "from requests: \(requests)\(since == nil ? " — every step that landed since launch" : " — request \(since ?? 1) on"); a walk takes it from launch",
            "states: \(screen.states.map(Self.json).joined(separator: ", ")) — \(stateSource)",
        ]
        if let expect = screen.expect {
            residue.append("expect: \(expect)")
        }
        if existing != nil {
            residue.append("re-encoded: \(path.tildedPath) was decoded and written back whole — pretty-printed, keys sorted; its own layout and key order are not kept")
        }
        residue.append("replay it: simwalk walk \(path.tildedPath) --screens \(screen.id) --output <new bundle>.simwalk")
        let target = existing.map { "walkbook '\($0.name)' (now \($0.screens.count + 1) screens)" } ?? "a new walkbook"
        return Answer(
            header: "live session: \(sessionID)  app: \(launch.appBundleID)",
            verdict: .reporting(
                qualifications: unlanded.map { "request \($0.n): \($0.step.map { "\($0)" } ?? "a step") was taken and did not land, so it is not in the saved route — if it changed the app, a replay may drift" },
                detail: "saved screen '\(screen.id)' (\(steps)) into \(target) at \(path.tildedPath)"
            ),
            residue: residue
        )
    }

    private static func json(_ state: Walkbook.CaptureState) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(state)).flatMap { String(data: $0, encoding: .utf8) } ?? state.slug
    }
}
