//
// Copyright © Agulhas Labs
//

import Foundation

/// Whether the status line renders, as a marker file beside its scan cache.
///
/// Hiding is a render-time switch rather than an unregistration, because `install-hook` runs on every upgrade: a registration deleted by hand would quietly come back with the next install, while a registered command that prints nothing stays silent across upgrades. An empty segment displays as no segment at all — the same silence a session that never called already produces.
public struct StatuslineVisibility {
    private let markerURL: URL

    public init(cacheDirectory: URL) {
        markerURL = cacheDirectory.appendingPathComponent("hidden")
    }

    /// The standard location, sharing the scan cache's directory — which means the hide/show marker moves with `SIMWALK_USAGE_LOG` too: hiding the status line under a test's or a review's override cannot hide it for the real log, and the reverse.
    public static func standard() -> StatuslineVisibility {
        StatuslineVisibility(cacheDirectory: SimWalkPaths.statuslineCacheDirectory)
    }

    public var isHidden: Bool {
        FileManager.default.fileExists(atPath: markerURL.path)
    }

    /// Writes the marker, reporting whether it was newly written.
    @discardableResult
    public func hide() throws -> Bool {
        guard !isHidden else { return false }
        try FileManager.default.createDirectory(at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: markerURL)
        return true
    }

    /// Removes the marker, reporting whether there was one to remove.
    @discardableResult
    public func show() throws -> Bool {
        guard isHidden else { return false }
        try FileManager.default.removeItem(at: markerURL)
        return true
    }
}
