//
// Copyright © Agulhas Labs
//

import Foundation

/// Answers `simwalk inspect`: the screen an app is on right now, in the form `bundle screen` serves a captured one — its identifier and its text in accessibility order (SimWalk#49).
///
/// **The first residue line is the screen's hash** (`screen <hash>`, ``ScreenHash``): what a live session's `step` can be guarded by, so a step never lands on a screen that changed since this read.
///
/// **The listing is `bundle screen`'s own code** (``BundleScreenQuery/text(of:match:listingOffScreen:offScreenHint:stillNeeding:)``), so `--match` narrows a live read exactly as it narrows a captured one and a route written from either names the same labels.
///
/// **Priced against the one screenshot it stands in for** — the device's own screen size, at the same token rule a bundle's screenshot is weighed by — because a screenshot is what a route author took before this existed. With no screen size recorded there is no saving line, never a guessed one.
public struct LiveScreenQuery {
    private let screen: LiveScreen
    private let qualifications: [String]
    private let notes: [String]

    /// What a live read is logged as — the CLI verb itself.
    public static var logName: String {
        "inspect"
    }

    /// - Parameters:
    ///   - qualifications: what the run knows and the file cannot — a runner failure the read survived, a device not handed back as it was found — each qualifying the verdict.
    ///   - notes: lines printed under the listing, after a blank line: what the run handed the device back in.
    public init(_ screen: LiveScreen, qualifiedBy qualifications: [String] = [], notes: [String] = []) {
        self.screen = screen
        self.qualifications = qualifications
        self.notes = notes
    }

    /// The answer, or a refusal naming why there was nothing to read.
    ///
    /// - Parameter match: narrows the text to elements whose label or value contains it, case-insensitively.
    /// - Parameter screenshot: what became of the screenshot, its line (``ScreenshotFit/line(_:)``) put right after the `screen <hash>` line.
    public func answer(match: String? = nil, screenshot: ScreenshotFit.Outcome? = nil) throws -> Answer {
        guard let tree = screen.tree, screen.appState != .notRunning else {
            throw LiveScreenError.appNotRunning(bundleID: screen.appBundleID, udid: screen.device.udid)
        }
        // A written screenshot answers the visual question the text hint would send to one, so the read stands in for no screenshot and weighs nothing.
        let wrote = switch screenshot {
        case .written: true
        case .refused, nil: false
        }
        let text = BundleScreenQuery.text(
            of: tree,
            match: match,
            stillNeeding: wrote ? "a look at the screenshot it wrote" : "a screenshot (--screenshot on this read, or screenshot: true over MCP)"
        )
        let forward = screen.appState == .background ? " (brought forward from the background)" : ""
        let detail = "live read of \(screen.appBundleID)\(forward) — \(text.clause)"
        let qualifications = [
            AnswerVerdict.qualification(screen.settled == false ? 1 : 0, "read", "taken while the tree was still changing"),
        ].compactMap(\.self) + qualifications
        return Answer(
            header: header,
            verdict: AnswerVerdict.reporting(qualifications: qualifications, detail: detail),
            residue: ["screen \(ScreenHash.of(tree, pixels: screen.pixels))"] + [screenshot.map(ScreenshotFit.line), pixelsLine].compactMap(\.self) + text.residue + (notes.isEmpty ? [] : [""] + notes),
            weighing: wrote ? nil : screen.screenPixels.map { ContextSaving(screenshotTokens: [ImageTokenEstimate.tokens(width: $0.width, height: $0.height)], treeBytes: 0, servedBytes: 0) }
        )
    }

    /// A text-less screen's hash moves with its picture, which a read would otherwise not say: a step says it on its delta's `pixels:` line, and an agent comparing two reads of an animating screen needs it as much (SimWalk#223).
    private var pixelsLine: String? {
        screen.pixels == nil ? nil : "pixels: hashed (\(ScreenDelta.pixelHashReason)), so a picture that moves moves the hash"
    }

    private var header: String {
        Self.header(of: screen)
    }

    /// The header: what was read, and by which runner — no time and no UDID, which are provenance and stay in the file.
    ///
    /// Shared with ``LiveSessionStepQuery``, whose answer is of the same screen.
    static func header(of screen: LiveScreen) -> String {
        [
            "live: app: \(screen.appBundleID)",
            screen.runnerCommit.map { "runner: \(ShortHash.of($0))\($0.contains("-dirty") ? "-dirty" : "")" },
            "device: \(screen.device.name) (\(screen.device.osVersion))",
        ].compactMap(\.self).joined(separator: "  ")
    }
}
