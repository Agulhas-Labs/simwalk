//
// Copyright © Agulhas Labs
//

import Foundation

/// Measures a bundle's artefacts on disk.
///
/// `CaptureBundleSummary` reports the walk; this reports the bundle. The two are deliberately different questions, and the second only becomes interesting once nobody watched the first — a bundle read a week later, or on another machine, has a manifest that says `captured` and files that may or may not still be worth reading.
///
/// `CaptureBundle.read` already refuses a manifest claiming an artefact that is absent, so nothing here re-checks presence. What it adds is **size**, which presence cannot speak to: a zero-byte screenshot is present, passes every structural check, and depicts nothing.
public struct CaptureBundleContents {
    private let bundle: CaptureBundle
    private let fileManager: FileManager

    public init(_ bundle: CaptureBundle, fileManager: FileManager = .default) {
        self.bundle = bundle
        self.fileManager = fileManager
    }

    /// One entry per screen, in manifest order.
    public func screens() -> [ScreenContents] {
        bundle.manifest.screens.map { screen in
            let artefacts = screen.captures.flatMap { capture in
                [
                    Artefact(path: capture.screenshotPath, bytes: size(ofRelativePath: capture.screenshotPath)),
                    Artefact(path: capture.axTreePath, bytes: size(ofRelativePath: capture.axTreePath)),
                ]
            }
            return ScreenContents(id: screen.id, captureCount: screen.captures.count, artefacts: artefacts)
        }
    }

    /// The bytes of the manifest and every capture it describes that could be measured — not every byte the bundle directory holds.
    ///
    /// An artefact whose size could not be read contributes nothing here and is listed by `unmeasurableArtefacts()` instead, so a total is never quietly short by a file nobody was told about. Nor does it see anything the manifest does not name: a `simwalk-retry-*` scratch bundle left behind by a walk killed while its second runner was still running, before any fold began (SimWalk#26, a known limit) sits in the bundle directory and is not counted, since it belongs to no screen the manifest records.
    public func totalBytes() -> Int {
        var total = size(ofRelativePath: CaptureBundleLayout.manifestFileName) ?? 0
        for screen in screens() {
            total += screen.bytes
        }
        return total
    }

    /// Artefacts that exist and hold nothing — present to every structural check, and empty.
    public func emptyArtefacts() -> [Artefact] {
        screens().flatMap(\.artefacts).filter { $0.bytes == 0 }
    }

    /// Artefacts whose size could not be read at all — a permissions failure, a broken symlink, a file that vanished between the manifest being read and this being asked.
    ///
    /// Its own answer, because it used to be the same one as empty: a failed `stat` returned zero and the artefact was reported as "present, and holding nothing", which is a specific and checkable claim about a file nothing had managed to look at.
    public func unmeasurableArtefacts() -> [Artefact] {
        screens().flatMap(\.artefacts).filter { $0.bytes == nil }
    }

    private func size(ofRelativePath path: String) -> Int? {
        let url = CaptureBundleLayout.url(forRelativePath: path, in: bundle.url)
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.size] as? Int
    }
}

public extension CaptureBundleContents {
    /// One screen's artefacts on disk.
    struct ScreenContents: Equatable, Sendable {
        public let id: String
        public let captureCount: Int
        public let artefacts: [Artefact]

        /// The bytes that could be measured.
        public var bytes: Int {
            artefacts.reduce(0) { $0 + ($1.bytes ?? 0) }
        }

        /// How many of this screen's artefacts could not be measured, so a size is never read as complete when it is not.
        public var unmeasurableCount: Int {
            artefacts.count { $0.bytes == nil }
        }
    }

    /// One file inside a bundle, with its size — `nil` when the size could not be read, which is a different fact from zero.
    struct Artefact: Equatable, Sendable {
        public let path: String
        public let bytes: Int?

        public init(path: String, bytes: Int?) {
            self.path = path
            self.bytes = bytes
        }
    }
}
