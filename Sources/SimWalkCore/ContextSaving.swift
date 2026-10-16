//
// Copyright © Agulhas Labs
//

import Foundation

/// What one answer stood in for, priced in the context it kept out of the window.
///
/// The claim a resolved observation makes is that a reader did not have to open the raw material, so the honest way to state its worth is to weigh the raw material it stood in for and subtract what the answer itself cost. Both halves are measured — the screenshots by their pixels (``ImageTokenEstimate``), the accessibility trees by their bytes (``TokenEstimate``), the answer by its own bytes — and neither is modelled.
///
/// **It is a floor, and every rendering says so.** Only what *this* answer stood in for is counted: not the walk that produced the bundle, not the reading a caller would have done around it, and not any answer that weighed nothing. Where nothing could be weighed there is no value at all rather than a saving of zero — an absence and a zero are different claims, and only one of them is true of an answer that stands in for nothing.
public struct ContextSaving: Equatable, Sendable {
    /// What each screenshot this answer stands in for would have cost to look at.
    public let screenshotTokens: [Int]

    /// The bytes of accessibility tree this answer stands in for.
    public let treeBytes: Int

    /// The bytes of the answer itself — what was spent instead.
    public let servedBytes: Int

    public init(screenshotTokens: [Int], treeBytes: Int, servedBytes: Int) {
        self.screenshotTokens = screenshotTokens
        self.treeBytes = treeBytes
        self.servedBytes = max(0, servedBytes)
    }

    /// Weighs every capture `bundle` holds, or answers `nil` when there was nothing to weigh.
    ///
    /// An artefact that cannot be read — a screenshot that is not a PNG this understands, a tree whose size the filesystem will not report — is left out rather than guessed at, which keeps the figure a floor by the same rule that chose every constant behind it. A bundle holding no readable artefact at all weighs nothing, and an answer over it says nothing about a saving.
    public static func weighing(_ bundle: CaptureBundle, servedBytes: Int = 0, fileManager: FileManager = .default) -> ContextSaving? {
        var screenshots: [Int] = []
        var trees = 0
        for capture in bundle.manifest.screens.flatMap(\.captures) {
            let weighed = Self.weighed(capture, in: bundle, fileManager: fileManager)
            if let tokens = weighed.screenshotTokens {
                screenshots.append(tokens)
            }
            trees += weighed.treeBytes
        }
        guard !screenshots.isEmpty || trees > 0 else { return nil }
        return ContextSaving(screenshotTokens: screenshots, treeBytes: trees, servedBytes: servedBytes)
    }

    /// Weighs one capture — the screenshot a single-screen answer stands in for, never its tree — or answers `nil` when the screenshot could not be read.
    ///
    /// `bundle screen` reads one capture rather than a bundle's worth, and pricing it against every screenshot the bundle holds would claim a saving on captures it never opened (SimWalk#20) — the same floor rule as the whole-bundle weighing above, at the grain the caller actually asked about. **The tree is left out of the arithmetic entirely, not merely out of the bundle-wide total**: a reader answering a text question opens the screenshot or reads the tree, never both, so charging both would claim a saving nobody would actually have taken (SimWalk#20 round 2, §2).
    public static func weighing(_ bundle: CaptureBundle, capture: CaptureManifest.StateCapture, servedBytes: Int = 0, fileManager: FileManager = .default) -> ContextSaving? {
        guard let tokens = weighed(capture, in: bundle, fileManager: fileManager).screenshotTokens else { return nil }
        return ContextSaving(screenshotTokens: [tokens], treeBytes: 0, servedBytes: servedBytes)
    }

    /// The same weighing priced against an answer of `bytes`.
    public func served(_ bytes: Int) -> ContextSaving {
        ContextSaving(screenshotTokens: screenshotTokens, treeBytes: treeBytes, servedBytes: bytes)
    }

    /// What the material this answer replaced would have cost.
    public var replacedTokens: Int {
        screenshotTokens.reduce(0, +) + TokenEstimate.tokens(forBytes: treeBytes)
    }

    /// What the answer cost instead.
    public var servedTokens: Int {
        TokenEstimate.tokens(forBytes: servedBytes)
    }

    /// The saving, which is never negative: an answer that cost more than what it stood in for saved nothing, and saying so is not the same as saying it cost the difference.
    public var savedTokens: Int {
        Self.saved(imageTokens: screenshotTokens.reduce(0, +), treeBytes: treeBytes, servedBytes: servedBytes)
    }

    /// The same subtraction from totals alone — what a usage log can reconstruct, having recorded what each call weighed but not each screenshot separately.
    ///
    /// One generator for the arithmetic, so a line's own answer and the report over a month of them cannot come to price the same call differently.
    public static func saved(imageTokens: Int, treeBytes: Int, servedBytes: Int) -> Int {
        max(0, imageTokens + TokenEstimate.tokens(forBytes: treeBytes) - TokenEstimate.tokens(forBytes: servedBytes))
    }

    /// The last line of every answer that stood in for something: the figure, the arithmetic behind each half of it, and why it is a floor.
    public var line: String {
        "\(headline) — \(replaced), against \(served). A floor: only what this answer stood in for is counted."
    }
}

private extension ContextSaving {
    /// One capture's screenshot tokens (`nil` when its screenshot cannot be read as a PNG this understands) and tree bytes (`0` when its tree's size cannot be read) — what both weighings above are built from, so a bundle-wide saving and a one-capture saving can never measure the same file two different ways.
    static func weighed(_ capture: CaptureManifest.StateCapture, in bundle: CaptureBundle, fileManager: FileManager) -> (screenshotTokens: Int?, treeBytes: Int) {
        let screenshotTokens = PNGSize(contentsOf: bundle.screenshotURL(for: capture)).map(ImageTokenEstimate.tokens(of:))
        let attributes = try? fileManager.attributesOfItem(atPath: bundle.axTreeURL(for: capture).path)
        return (screenshotTokens, attributes?[.size] as? Int ?? 0)
    }

    /// The figure the line leads with, or the honest absence of one.
    var headline: String {
        savedTokens > 0 ? "\(TokenEstimate.short(savedTokens)) saved" : "no tokens saved"
    }

    /// What was weighed, each half with the constant it was weighed by — and nothing at all for a half that weighed nothing.
    var replaced: String {
        [screenshotsClause, treesClause].compactMap(\.self).joined(separator: " and ")
    }

    var screenshotsClause: String? {
        guard let first = screenshotTokens.first else { return nil }
        let cap = "at the \(ImageTokenEstimate.longEdgeCap) px cap"
        if screenshotTokens.count == 1 {
            return "1 screenshot (\(TokenEstimate.magnitude(first)) \(cap))"
        }
        // "each" is a claim about every one of them, so it is made only when they are in fact alike —
        // which one device walking one app is, and a bundle stitched from several is not.
        guard screenshotTokens.allSatisfy({ $0 == first }) else {
            return "\(screenshotTokens.count) screenshots (\(TokenEstimate.magnitude(screenshotTokens.reduce(0, +))) in total \(cap))"
        }
        return "\(screenshotTokens.count) screenshots (\(TokenEstimate.magnitude(first)) each \(cap))"
    }

    var treesClause: String? {
        guard treeBytes > 0 else { return nil }
        return TokenEstimate.basis(bytes: treeBytes, of: "accessibility trees")
    }

    /// The served figure, which is converted at the byte ratio too — so the ratio is stated beside it whenever the trees clause, which states it for both, is absent: a one-screen answer weighs no tree, and its served kB would otherwise become tokens at a ratio the line never gave.
    var served: String {
        let bytes = ByteSize.short(servedBytes)
        guard treesClause == nil, servedBytes > 0 else { return "\(bytes) served" }
        return "\(bytes) served at \(TokenEstimate.bytesPerToken) bytes a token"
    }
}
