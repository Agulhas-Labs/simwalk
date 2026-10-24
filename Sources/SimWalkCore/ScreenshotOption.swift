//
// Copyright © Agulhas Labs
//

import Foundation

/// The three inputs a read takes for a screenshot, and the one place they become a ``ScreenshotFit/Request`` (SimWalk#200).
///
/// `inspect` and `session read` share it, and the MCP face reaches it through the command line, so a scale outside 1…3 is refused in one wording whichever face it came from.
public struct ScreenshotOption {
    private init() {}

    /// How many `inspect` screenshots are kept in the state directory.
    public static let keptCount = 20

    /// The request the options ask for, or `nil` when none is asked for.
    ///
    /// A scale or a label implies the screenshot, since neither means anything without one. Throws for a scale outside 1…3.
    public static func request(screenshot: Bool, scale: Int?, of label: String?) throws -> ScreenshotFit.Request? {
        guard screenshot || scale != nil || label != nil else { return nil }
        let chosen = scale ?? 1
        guard let request = ScreenshotFit.Request(scale: chosen, label: label) else {
            throw Refusal(description: "--screenshot-scale takes 1, 2 or 3 pixels per point; \(chosen) is none of them")
        }
        return request
    }

    /// The outcome for `png`, fitted and written to `url`, or the refusal saying why there is no file.
    ///
    /// `png` absent is the runner's refusal when it gave one, else `absentReason`. A file that cannot be written or decoded is a refusal line as well, so a screenshot that fails never costs the read it rode on.
    public static func outcome(png: Data?, refusal: String?, absentReason: String, tree: AXNode, request: ScreenshotFit.Request, to url: URL) -> ScreenshotFit.Outcome {
        guard let png else {
            return .refused(refusal ?? absentReason)
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            return try ScreenshotFit.write(png: png, tree: tree, request: request, to: url)
        } catch {
            return .refused("\(error)")
        }
    }

    /// Removes all but the newest ``keptCount`` `inspect-*.png` files in `directory`, newest by modification date; a missing directory is nothing to prune.
    ///
    /// Run after each `inspect` that wrote one, so the state directory holds a bounded number of images however often it is used. Files that do not match the name are never touched.
    public static func prune(_ directory: URL, keeping: Int = keptCount) {
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let dated = files
            .filter { $0.lastPathComponent.hasPrefix("inspect-") && $0.pathExtension == "png" }
            .map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
        for (url, _) in dated.dropFirst(max(keeping, 0)) {
            try? manager.removeItem(at: url)
        }
    }
}

public extension ScreenshotOption {
    /// A scale the request cannot carry, named so the caller sees which value was refused.
    struct Refusal: Error, CustomStringConvertible, Equatable {
        public let description: String
    }
}
