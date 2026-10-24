//
// Copyright © Agulhas Labs
//

import Foundation

/// What the runner writes for `simwalk inspect`: one read of an app's accessibility tree as it stands on the device, with nothing launched and nothing captured (SimWalk#49).
///
/// **The app's state is the first fact, and a tree is present only when there was an app to read.** The runner attaches by bundle identifier and never launches: an app found not running is written as ``AppState/notRunning`` with no tree, so the host refuses with the reason rather than the runner starting the app and serving its launch screen as the screen somebody left it on.
///
/// **Read twice, a settle interval apart, and kept as the second read.** `settled` says whether the two agreed by ``ScreenIdentity``: one read alone cannot tell a screen at rest from one mid-push, and a route written from a transition names labels that are gone a moment later.
public struct LiveScreen: Codable, Equatable, Sendable {
    /// The format this build writes.
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    /// The app the runner attached to.
    public let appBundleID: String
    /// The device it was read on, from the runner's own process.
    public let device: CaptureManifest.Device
    /// The commit the runner that read it was built from; `nil` when the host could not tell.
    public let runnerCommit: String?
    /// When the runner took the read, by its own clock.
    public let readAt: Date
    /// The value the host generated and passed the runner, echoed back so an overlapping inspect's file is never read as this one's.
    public let nonce: String
    /// What the app was doing when the runner attached.
    public let appState: AppState
    /// The tree, when the app was running; `nil` for ``AppState/notRunning``.
    public let tree: AXNode?
    /// The tree's ``ScreenIdentity`` digest — the identity a walk compares before and after a step.
    public let screenIdentity: String?
    /// Whether a second read, a settle interval after the first, had the same identity; `nil` when there was no tree.
    public let settled: Bool?
    /// The device screen's size in pixels — what a screenshot of it would be, and what this read is priced against; `nil` when it could not be read.
    public let screenPixels: Pixels?
    /// The system alert SpringBoard draws over the app, which the app's own tree never shows; absent when none covers it, and absent from every read made before the field existed.
    public let systemAlert: SystemAlert?
    /// The screenshot reduced to a grid, taken only when the tree lists no text, so the screen hash can tell such screens apart (SimWalk#150); absent otherwise, and absent from every read made before the field existed.
    public let pixels: PixelSignature?

    public init(
        formatVersion: Int = LiveScreen.currentFormatVersion,
        appBundleID: String,
        device: CaptureManifest.Device,
        runnerCommit: String?,
        readAt: Date,
        nonce: String,
        appState: AppState,
        tree: AXNode?,
        settled: Bool?,
        screenPixels: Pixels?,
        systemAlert: SystemAlert? = nil,
        pixels: PixelSignature? = nil
    ) {
        self.formatVersion = formatVersion
        self.appBundleID = appBundleID
        self.device = device
        self.runnerCommit = runnerCommit
        self.readAt = readAt
        self.nonce = nonce
        self.appState = appState
        self.tree = tree
        screenIdentity = tree.map { ScreenIdentity.of($0).digest }
        self.settled = settled
        self.screenPixels = screenPixels
        self.systemAlert = systemAlert
        self.pixels = pixels
    }
}

public extension LiveScreen {
    /// What the app was doing when the runner attached to it.
    enum AppState: String, Codable, Equatable, Sendable {
        /// In the foreground, read as it stood.
        case foreground
        /// Running but not frontmost, and brought forward with `activate()` — which resumes a running app and never relaunches it.
        case background
        /// Not running at all, so there was nothing to read and nothing was launched.
        case notRunning = "not-running"
    }

    /// A screen's size in pixels.
    struct Pixels: Codable, Equatable, Sendable {
        public let width: Int
        public let height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    /// A system alert over the app: its title and the buttons it offers, which a reader lists and never taps.
    struct SystemAlert: Codable, Equatable, Sendable {
        /// The alert's title, or `nil` when it has none.
        public let title: String?
        /// Its buttons, in the order SpringBoard's tree lists them.
        public let buttons: [Button]

        public init(title: String?, buttons: [Button]) {
            self.title = title
            self.buttons = buttons
        }
    }

    /// Writes the read to `url`, never replacing a file already there.
    func write(to url: URL) throws {
        do {
            try CaptureBundle.encoder().encode(self).write(to: url, options: .withoutOverwriting)
        } catch {
            throw LiveScreenError.notWritable(path: url.path, reason: error.localizedDescription)
        }
    }

    /// Reads the file at `url`, refusing one this run did not ask for: of an app other than `appBundleID`, or carrying a nonce other than `nonce` — the one this run generated and passed its own runner.
    static func read(at url: URL, appBundleID: String, nonce: String) throws -> LiveScreen {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LiveScreenError.missing(path: url.path, reason: error.localizedDescription)
        }
        let screen: LiveScreen
        do {
            screen = try CaptureBundle.decoder().decode(LiveScreen.self, from: data)
        } catch {
            throw LiveScreenError.malformed(path: url.path, reason: "\(error)")
        }
        guard screen.formatVersion == currentFormatVersion else {
            throw LiveScreenError.unsupportedFormatVersion(path: url.path, found: screen.formatVersion, supported: currentFormatVersion)
        }
        guard screen.appBundleID == appBundleID, screen.nonce == nonce else {
            throw LiveScreenError.fromAnotherRun(path: url.path)
        }
        return screen
    }
}

public extension LiveScreen.SystemAlert {
    /// One button of the alert.
    struct Button: Codable, Equatable, Sendable {
        public let label: String
        /// Where it is drawn.
        public let frame: AXNode.Frame

        public init(label: String, frame: AXNode.Frame) {
            self.label = label
            self.frame = frame
        }
    }
}
